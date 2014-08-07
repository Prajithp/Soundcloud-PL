#!/usr/bin/perl

package SoundCloud;

use strict;

use LWP::UserAgent 	();
use Term::ProgressBar	();
use JSON::Tiny	   	();
use Carp	   	();
use File::Spec          ();
use Fcntl qw(O_WRONLY O_EXCL O_CREAT O_APPEND);

our $VERSION = '1.0';

use constant 'SOUDCLOUD_API' => 'http://api.soundcloud.com/';
use constant 'PLAYLIST_URL'   => 'https://api.soundcloud.com/playlists/';


sub new {
  my ($class, %args) = @_;
  
  my $self = { %args };
  
  die "I don't know what to do without soundcloud url" unless($self->{url});
  
  $self->{ua} ||= LWP::UserAgent->new(
    agent => __PACKAGE__.'/'.$VERSION,
    parse_head => 0,
  );

  bless($self, $class);
  
  $self->{url_type} = $self->guess_url($self->{url});
  
  return $self;
}

sub ua {
  my ($self, $ua) = @_;
  
  return $self->{ua} unless $ua;
  Carp::croak "Usage: $self->ua(\$LWP_LIKE_OBJECT)" unless eval { $ua->isa('LWP::UserAgent') };
  
  $self->{ua} = $ua;
}

sub guess_url {
  my ($self, $url) = @_;
  
  $url ||= $self->{url};
  
  # valid urls are
  
  # http://soundcloud.com/user/song-name 	[single_song]
  # http://soundcloud.com/user/sets/set-name	[playlist]
  
  # remove protocol from url
  $url =~ s|(http://\|https://)||;
  my $url_type;
  
  my ($host, $author, $type, $name) = split(/\//, $url);
  usage() unless($host =~ /soundcloud.com/ or !$author);
  
  if ($type ne 'sets' && !$name) {
    $url_type = 'single_song';
  }
  elsif($type eq 'sets' && $name) {
    $url_type = 'playlist';
  }
  else {
    die "I don't know how to proceed with this url: $url, correct this and try again";
  }
  
  return $url_type;
}

sub getClientId {
  my ($self, $page) = @_;
  
  my $jsTOJson = $1 if ($page =~ m{window.SC\s+=\s+(.*)}i);
  $jsTOJson =~ s/;//g;
  
  my $client_id = JSON::Tiny::decode_json($jsTOJson);
  
  return $client_id->{clientID} ? $client_id->{clientID} : '0';
}

sub fetch_song_info {
  my ($self, $song_url) = @_;
  
  $song_url ||= $self->{url};
  
  my $page = $self->_get_content($song_url);
  my $jsTOJson = $1 if ($page =~ m{window.SC.bufferTracks.push\((.*)}i);
  $jsTOJson =~ s/;//g;
  $jsTOJson =~ s/\)//g;
  
  my $song_info = JSON::Tiny::decode_json($jsTOJson);
  
  return $song_info;
}

sub getPlaylistInfo {
  my ($self, $playlist_url) = @_;
  
  my $info;
  my $page = $self->_get_content($playlist_url);
  $info->{clientid}    = $self->getClientId($page);
  $info->{playlist_id} = $1 if ($page =~ m{<meta content="soundcloud://playlists:(.+)/" property="al:ios:url" />}s);
  
  return $info;
}

sub retrivePlayList {
  my $self = shift;
  
  my $playlist_url  = $self->{url};
  my $playlist_info = $self->getPlaylistInfo($playlist_url);
  my $playlist_id   = $playlist_info->{playlist_id};
  my $client_id     = $playlist_info->{clientid};
  
  my $response = $self->ua->get(PLAYLIST_URL  . "$playlist_id.json?&client_id=$client_id");
  Carp::croak "failed to retrive json object: ", $response->status_line if $response->is_error;
  
  my $json_obj = JSON::Tiny::decode_json($response->content);

  return $json_obj->{tracks} ? $json_obj->{tracks} : [];
}

sub getplayableUrl {
  my ($self, $url) = @_;
  
  my $response = $self->ua->head($url);

  return $response->request->uri->as_string if $response->is_success;
}

sub _get_content {
  my ($self, $url) = @_;
  
  local $Carp::CarpLevel = $Carp::CarpLevel + 1;
  
  my $res = $self->ua->get($url);
  Carp::croak "GET $url failed. status: ", $res->status_line if $res->is_error;
  
  return $res->content;
}

sub Download {
  my ($self, $opts_ref) = @_;
    
  my $did_set_target = 0;
  my $received_size  = 0;
  my $next_update    = 0;
  my $content	     = undef;
  my $file_is_there  = '0';
  my $url            = $opts_ref->{url};
  my $filename       = $opts_ref->{filename};
  
  if (defined $opts_ref->{directory}) {
    $filename = File::Spec->catfile($opts_ref->{directory}, $filename);
  }
  
  if (-f $filename) {
    $file_is_there = 1;
  }
  
  local *FILE;
  if ($file_is_there && $opts_ref->{allow_override}) {
     open(FILE, '>', $filename) or die "can't open file $filename: $!";
  }
  else {
    sysopen(FILE, $filename, O_WRONLY|O_EXCL|O_CREAT|O_APPEND) or die "Can't open $filename: $!";  
  }
  
  my $progress = Term::ProgressBar->new({
      count      => 1024,
      ETA        => 'linear',
      term_width => '75',
      remove     => 1,
      silent	 => $opts_ref->{silent},
  });
  
  $progress->minor(0); # turns off the floating asterisks.
  $progress->max_update_rate(1); # only relevant when ETA is used.
  $progress->message("Downloading $opts_ref->{title} ........") unless($opts_ref->{silent});
  
  my $response = $self->ua->get($url, ':content_cb' => sub {
      my ($data, $cb_response, $protocol) = @_;
      unless ($did_set_target) {
	if (my $content_length = $cb_response->content_length) {
	  $progress->target($content_length);
	  $did_set_target = 1;
	} 
	else {
	  $progress->target($received_size + 2 * length $data);
	}
      }
      $received_size += length $data;
      $content .= $data;
      $next_update = $progress->update($received_size) if $received_size >= $next_update; ;
  });
  
  print FILE $content;
  close(FILE);

  return;
}

package main;

use Getopt::Long;
use Cwd qw(abs_path);

my $VERSION = '1.0.0';

my %opts = (
    'download_dir'	=> abs_path,
    'allow_override'	=> '0',
    'url'		=> undef,
    'silent'		=> '0',
    'just_play'		=> undef,
    'player'		=> '/usr/bin/mplayer',
    'url_type'		=> 'track',
);

GetOptions(
    'url=s'		=> \$opts{url},
    'download_dir=s'	=> \$opts{download_dir},
    'allow_override'	=> sub { $opts{allow_override} = '1'; },
    'silent'		=> \$opts{silent},
    'play'		=> \$opts{just_play},				
    'player=s'		=> \$opts{player},
    'version'		=> sub { print STDERR "$0 $VERSION\n"; exit; },
    'help'		=> \&usage,
) or usage();

unless(defined $opts{url}) {
  usage();
}

my $client = SoundCloud->new('url' => $opts{url});
my $url_type = $client->guess_url;

my %download_args = (
    'directory'	      => $opts{download_dir},
    'title'           => undef,
    'filename'	      => undef,
    'url'	      => undef,
    'allow_override'  => $opts{allow_override},
    'silent'          => $opts{silent},
);

if ($opts{just_play}) {
  if ($url_type eq 'single_song') {
    my $songinfo = $client->fetch_song_info();
    system($opts{player}, $client->getplayableUrl($songinfo->{streamUrl}));
  }
  elsif($url_type eq 'playlist') {
    my $hash = $client->retrivePlayList();
    
    foreach my $detail (@{$hash}) {
      my $songinfo = $client->fetch_song_info($detail->{permalink_url});
      system($opts{player}, $client->getplayableUrl($songinfo->{streamUrl}));
    }
  }
}
else {
  if ($url_type eq 'single_song') {
    my $songinfo = $client->fetch_song_info();    
    $download_args{title} = $songinfo->{title};
    $download_args{filename} = $songinfo->{name} . '.mp3';
    $download_args{url} = $songinfo->{streamUrl};
    
    $client->Download(\%download_args);
  }
  elsif($url_type eq 'playlist') {
    my $hash = $client->retrivePlayList();
    
    foreach my $detail (@{$hash}) {
      my $songinfo = $client->fetch_song_info($detail->{permalink_url});
      $download_args{title} = $songinfo->{title};
      $download_args{filename} = $songinfo->{name} . '.mp3';
      $download_args{url} = $songinfo->{streamUrl};
      
      $client->Download(\%download_args);
    }
  }
}


sub usage {
  print STDERR <<USAGE;
Usage:
    soundCloud-downloader --url <soundcloud url> [options]
Options:
    --download_dir	<path>		Where to save downloaded data.
    --allow_override			Overwrite the output file if exists.
    --silent				Don't display any output.
    --play				Don't download the file, just play the song.
    --player	/usr/bin/mplayer	set a media player, default is mplayer.
    --version				Display the version number.
    --help				show this message and exit.
URL example:
    http://soundcloud.com/user/song-name 	[single_song]
    http://soundcloud.com/user/sets/set-name	[playlist]
    
USAGE
  exit;
}
