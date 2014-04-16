#!/usr/bin/env ruby

require 'colorize'
require 'cheetah'
require 'optparse'
require 'mechanize'
require 'yaml'

def login_novell(user,pass)
  @agent = Mechanize.new
  page = @agent.get 'https://login.attachmategroup.com/nidp/app/login?id=17&sid=2&option=credential&sid=2'

  form = page.form('IDPLogin')
  form.Ecom_User_ID = user
  form.Ecom_Password = pass
  page = @agent.submit(form, form.buttons.first)

  if page.body.match /Login failed/
    puts "Login to Novell website failed for user #{user}".red
    exit
  end
  puts "Logged into Novell website as user #{user}".green if $options[:debug]
end

def get_novell_downloads(param = {})
  @agent = Mechanize.new
  
  # Use below for testing
  page = @agent.get 'file:///data/download-test/example.html'

  #login_novell param[:user], param[:pass]
  #page = @agent.get param[:url]

  urls = []
  rows = page.parser.xpath "//*[@id='dl_filelist']/table/tbody/tr"
  rows.each do |row|
    url = {}
    if row.at("td[3]")
      url[:name] = row.at("td[1]").text.strip
      url[:url]  = row.at("td[3]/a/@href").text
      urls << url
    end
  end

  # Sort by filename
  return urls.sort{ |a,b| a[:text] <=> b[:text] }
end

def test_download(param = {})
  if param[:name].nil?
    puts "   - Error: No name defined".red
    return
  end

  if param[:url].nil?
    puts "   - Error: No URL defined"
    return
  end

  puts "  Downloading: #{param[:name]}" if $options[:verbose]
  type = param[:type] ||= 'available'
  begin 
    Cheetah.run(
      "curl", 
      param[:url], 
      "-f", 
      "-L", 
      "--max-filesize", 
      "1024" )
    if type != 'unavailable'
      puts "   - [Success] Download finished: #{param[:name]}".green
    else 
      puts "   -  [Failed] Download finished of unavailable file: #{param[:name]}".red
    end

  rescue Cheetah::ExecutionFailed => e
    if type == 'available' && e.status.exitstatus == 63 
      puts "   - [Success] Download started: #{param[:name]}".green
    elsif type == 'unavailable' && e.status.exitstatus == 22
      puts "   - [Success] File is not available: #{param[:name]}".green
    elsif type == 'unavailable' && e.status.exitstatus == 63
      puts "   -  [Failed] File should not be available: #{param[:name]}".red
    else
      puts "   - Status: #{e.status.exitstatus}".red
      puts "     Error: #{e.message}".red
      puts "     Standard output: #{e.stdout}"
      puts "     Error output: #{e.stderr}"
    end
  end
end

begin
  $options = {}

  $configfile  = 'download.yaml'

  optparse = OptionParser.new do |opts|
    opts.banner = "Usage: download-test.rb [options]"

    $options[:configuration] = ""
    opts.on( '-f', '--configuration STRING', 'Configuration file' ) do |c|
      $options[:configuration] = c
      $configfile = c
    end

    $options[:debug] = false
    opts.on( '-d', '--debug', 'Show debug output' ) do
      $options[:debug] = true
    end

    $options[:nolist] = false
    opts.on( '-L', '--no-list', "Don't get list of files" ) do
      $options[:nolist] = true
    end

    $options[:test] = false
    opts.on( '-t', '--test', 'Run tests' ) do
      $options[:test] = true
    end

    $options[:testmode] = ""
    opts.on( '-T', '--testmode STRING', "Don't login, but file instead of download page" ) do |c|
      $options[:testmode] = c
    end

    $options[:verbose] = false
    opts.on( '-v', '--verbose', 'Show more output' ) do
      $options[:verbose] = true
    end
  end
  optparse.parse!

  config = begin
             YAML.load( File.open($configfile))
           rescue ArgumentError => e
             puts "Could not parse #{$configfile}: #{e.message}"
             exit
           end

  config["sites"].each do |site|
    puts "Checking site: #{site['name']}"
    
    urls = []
    if !$options[:nolist]
      # Check what's available
      if !site['novell-url'].nil?
        urls = get_novell_downloads url: site['novell-url'], user: site['user'], pass: site['pass']
        puts "  * Available Novell downloads:"
        urls.each do |url|
          puts "   - #{url[:name]}"
          #puts "     #{url[:url]}"
        end
      end
    end
    
    if $options[:test]
      # Check if available downloads can be downloaded
      if !$options[:nolist]
        puts "  * Testing available downloads:"
        urls.each do |u|
          test_download url: u[:url], name: u[:name], type: 'available'
        end
      end


      # Check if what should be there is available
      puts "  * Testing if specific files are available:"
      downloads = site['available-downloads'] 
      downloads.each do |d|
        if d['name'] && d['url']
          test_download url: d['url'], name: d['name'], type: 'available'
        elsif d['name']
          found = false
          urls.each do |u|
            if u[:name] == d['name']
              test_download url: u[:url], name: u[:name], type: 'available'
              found = true
              break
            end
          end
          if !found
            puts "   -  [Failed] Could not find file': #{d['name']}".red
          end
        end
      end

      # Check if what should not be there is available
      puts "  * Testing if specific files are not available:"
      downloads = site['unavailable-downloads'] ||= []
      downloads.each do |d|
        if d['regex']
          urls.each do |u|
            if u[:name].match d['regex']
              puts "   -  [Failed] Found file matching '#{d['regex']}': #{u[:name]}".red
            end
          end
        elsif d['name'] && d['url']
          test_download url: d['url'], name: d['name'], type: 'unavailable'
        elsif d[:name]
          urls.each do |u|
            if u[:name] == d[:name]
              test_download url: d['url'], name: d['name'], type: 'unavailable'
            end
          end
        else
          puts "Aborted: Couldn't find data in unavailable-downloads".red
          exit
        end
      end # Check if what should not be there is available
    end # Do tests
  end # Loop sites
end