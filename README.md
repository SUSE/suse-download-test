suse-download-test
==================

Testscript to check availability of beta versions of SUSE Linux
Enterprise products.  The script is written in ruby and uses the the
Mechanize module to access the Novell/SUSE download servers used in SUSE
Beta tests.

Usage:

Edit the configuration file suse-betas.yaml to fit your needs. You need
credentials for each beta site you want to access. These credentials may
go directly into the config file like

sites:
  - name: Betatest SLES 12
    user: YOUR_USERNAME
    pass: YOUR_PASSWORD
  - name: Betatest SLED 12
    user: YOUR_USERNAME
    pass: YOUR_PASSWORD


or in case you want to use version control for the config, but not the
credentials, put them into a separate file, using the above in
credentials.yaml and below in the config file:

sites:
  - name: Betatest SLES 12
    user: EXTERN 

  - name: Betatest SLED 12
    user: EXTERN 

Start the script e.g. with

suse-downloads.rb -l -t

to check all listed files '-l' and perform all defined tests '-t'. 
The output goes to STDOUT and is colored by default, which can be
switched off using '-C'. This is useful for automatic checks, where
results are mailed, see test.sh script as an example.

See all available options with '-h' option.


Written by Uwe Drechsel. Licensed with GPL V2.
