#!/usr/bin/env ruby

require 'colorize'
require 'cheetah'
require 'optparse'
require 'mechanize'
require 'yaml'

class Stats
  def initialize
    @@tests_passed_count = 0
    @@tests_failed_count = 0
  end

  def self.test_passed
    @@tests_passed_count += 1
  end

  def self.test_failed
    @@tests_failed_count += 1
  end
  
  def tests_passed_count
    @@tests_passed_count
  end
  def tests_failed_count
    @@tests_failed_count
  end
end

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
  puts "Logged into Novell website as user #{user}".blue if $options[:debug]
end

def get_novell_downloads(param = {})
  @agent = Mechanize.new
  
  page = ""
  if !$options[:testmode].empty?
    # Use below for testing
    path = File.realpath $options[:testmode]
    puts "Testmode: Getting file:#{path}".blue
    page = @agent.get "file://#{$options[:testmode]}"
  else
    login_novell param[:user], param[:pass]
    page = @agent.get param[:url]
  end

  urls = []
  rows = page.parser.xpath "//*[@id='dl_filelist']/table/tr"

  rows.each do |row|
    url = {}
    if row.at("td[3]")
      url[:name] = row.at("td[1]").text.strip
      url[:url] = row.at("td[3]/a/@href").text
      url[:url] = 'http://download.novell.com' + url[:url] if $options[:testmode]
      urls << url
    end
  end

  # Sort by filename
  return urls.sort{ |a,b| a[:text] <=> b[:text] }
end

def log_result( success, testname, sitename )
  result = success ? '[Passed]' : '[Failed]'
  color  = success ? :green : :red
  s = "   - #{result} #{testname} for '#{sitename}'"
  if $options[:nocolor]
    puts s
  else
    puts s.colorize(color)
  end

  if success
    Stats::test_passed
  else
    Stats::test_failed
  end
end

def test_download(param = {})
  if param[:name].nil?
    puts "   - Error: No name defined".red
    return
  end

  if param[:url].nil?
    puts "   - Error: No URL defined".red
    return
  end

  if param[:sitename].nil?
    puts "   - Error: No testsite defined".red
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
      "--max-filesize", "1024" )

    if type == 'unavailable'
      log_result(
        false, 
        "File is not available: '#{param[:name]}' (download completed)",
        param[:sitename] )
    else
      log_result(
        true, 
        "File is available: '#{param[:name]}' (download completed)",
        param[:sitename] )
    end

  rescue Cheetah::ExecutionFailed => e
    if type == 'available' && e.status.exitstatus == 63 
      log_result true, "File is available: '#{param[:name]}' (download started)", param[:sitename]
    elsif type == 'unavailable' && e.status.exitstatus == 22
      log_result true, "File is not available: '#{param[:name]}'", param[:sitename]
    elsif type == 'unavailable' && e.status.exitstatus == 63
      log_result false, "File is not available: '#{param[:name]}'", param[:sitename]
    else
      puts "   - Status: #{e.status.exitstatus}".red
      puts "     Error: #{e.message}".red
      puts "     Standard output: #{e.stdout}"
      puts "     Error output: #{e.stderr}"
    end
  end
end

begin
  stats = Stats.new

  $options = {}

  $configfile  = 'suse-betas.yaml'

  optparse = OptionParser.new do |opts|
    opts.banner = "Usage: download-test.rb [options] [ALIAS]"

    $options[:configuration] = ""
    opts.on( '-f', '--configuration STRING', 'Configuration file' ) do |c|
      $options[:configuration] = c
      $configfile = c
    end

    $options[:nocolor] = false
    opts.on( '-C', '--no-color', "Don't color the output (useful for mails)" ) do
      $options[:nocolor] = true
    end

    $options[:debug] = false
    opts.on( '-d', '--debug', 'Show debug output' ) do
      $options[:debug] = true
    end

    $options[:list] = false
    opts.on( '-l', '--list', "Show list of files" ) do
      $options[:list] = true
    end

    $options[:nolisttest] = false
    opts.on( '-L', '--no-list-test', "Don't test list of available files" ) do
      $options[:nolisttest] = true
    end

    $options[:test] = false
    opts.on( '-t', '--test', 'Run tests' ) do
      $options[:test] = true
    end

    $options[:testmode] = ""
    opts.on( '-T', '--testmode STRING', "Parse file instead of online page to find downloads" ) do |c|
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
    if ARGV.empty? ||  ARGV.include?(site['alias']) 
      puts "Checking site: #{site['name']}"

      urls = []
      # Check what's available
      if !site['novell-url'].nil?
        urls = get_novell_downloads url: site['novell-url'], user: site['user'], pass: site['pass']
        if $options[:list]
          puts "  * Available Novell downloads:"
          urls.each do |url|
            puts "   - #{url[:name]}"
            #puts "     #{url[:url]}"
          end
        end
      end
      
      if $options[:test]
        # Check if available downloads can be downloaded
        if !$options[:nolisttest] && site['available-downloads'].include?({'autocheck' => true})
          puts "  * Testing available downloads:" 
          urls.each do |u|
            test_download url: u[:url], name: u[:name], type: 'available', sitename: site['name']
          end
        end


        # Check if what should be there is available
        puts "  * Testing if specific files are available:"
        downloads = site['available-downloads'] ||= []
        downloads.each do |d|
          if d['regex']
            log_result( 
             urls.map{ |x| x[:name]}.grep(/#{d['regex']}/).any?, 
             "One or more files match '#{d['regex']}'",
             site['name'])
          elsif d['name'] && d['url']
            test_download url: d['url'], name: d['name'], type: 'available', sitename: site['name']
          elsif d['name']
            found = false
            urls.each do |u|
              if u[:name] == d['name']
                test_download url: u[:url], name: u[:name], type: 'available', sitename: site['name']
                found = true
                break
              end
            end
            if !found
              log_result(
                false,
                "File is not available: '#{d['name']}' (No URL found in downloads)",
                site['name'])
            end
          end
        end

        # Check if what should not be there is available
        puts "  * Testing if specific files are not available:"
        downloads = site['unavailable-downloads'] ||= []
        downloads.each do |d|
          if d['regex']
            log_result(
              !urls.map{ |x| x[:name]}.grep(/#{d['regex']}/).any?,
              "File matching '#{d['regex']}' should not be available",
              site['name']
            )
          elsif d['name'] && d['url']
            puts "Found name and url".blue
            test_download url: d['url'], name: d['name'], type: 'unavailable', sitename: site['name']
          elsif d['name']
            urls.each do |u|
              if u[:name] == d['name']
                test_download url: u[:url], name: d['name'], type: 'unavailable', sitename: site['name']
              end
            end
          else
            puts "Aborted: Couldn't find data in unavailable-downloads".red
            exit
          end
        end # Check if what should not be there is available
      end # Do tests
    end # Check specific site
  end # Loop sites

  puts
  puts "Test passed: #{stats.tests_passed_count}"
  puts "Test failed: #{stats.tests_failed_count}"

  exit 1 if stats.tests_failed_count > 0 
end