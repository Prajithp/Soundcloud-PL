Soundcloud-PL
=============

Yet another Soundcloud music downloader

## Description

This is a simple soundcloud downloader I wrote in perl,
you can use this script to download music from http://www.soundcloud.com.
It should work with OS X, any Linux OS and Windows.

## System requirements

* Perl 5.000
* OS (Linux or OS X or Windows)

## Required Modules

* LWP::UserAgent
* Term::ProgressBar
* JSON::Tiny
* Carp          # Core module since 5.000
* File::Spec    # Core module since 5.005
* Fcntl         # Core module since 5.000
* Getopt::Long  # Core module since 5.000
* Cwd           # Core module since 5.000

Use cpanminus to install those modules, simply execute the command below as root or using sudo
```
curl -L http://cpanmin.us | perl - module name here
              OR
cpan install module name here              

# If you don't have curl but wget, replace `curl -L` with `wget -O -`.
```

## Instructions

1. Download [this](https://github.com/Prajithp/Soundcloud-PL/archive/master.zip)
2. Unzip
3. Install missing perl modules
5. Type `./soundcloud_dl.pl --url {URL} {OPTION}`


## License

[GPL v3](https://raw.githubusercontent.com/Prajithp/Soundcloud-PL/master/LICENSE)
