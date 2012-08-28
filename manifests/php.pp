# Define: nginx::server::vhost
#
#   nginx vhost. For serving web traffic as you would with apache.
#
# Parameters:
#
# Requires:
#   include nginx::server
#
define nginx::php(
  #$dest,
  $fpm_socket     = 'http://127.0.0.1:9000',
  $priority       = '10',
  $template       = 'nginx/vhost-php.conf.erb',
  $servername     = '',
  $path           = '',
  $auth           = '',
  $magic          = '',
  $port           = 80,
  $ssl            = false,
  $ssl_port       = 443,
  $sslonly        = false,
  $serveraliases  = undef,
  $isdefaultvhost = false,
  $aliases        = {},
  ) {

  include nginx

  apt::source { "dotdeb":
    location    => "http://packages.dotdeb.org",
    repos       => 'all',
    key         => '89DF5277',
    key_source  => "http://www.dotdeb.org/dotdeb.gpg",
    include_src => false,
  }

  package { "php5-cli":
    ensure  => present,
    require => Apt::Source['dotdeb'],
  }

  package { ['php5-common', 'php5-suhosin', 'php5-fpm', 'php5-cgi']:
    ensure  => present,
    require => [Apt::Source['dotdeb'], Package['php5-cli']],

  }

  service {$nginx::params::phpfpm_service:
    ensure     => running,
    hasrestart => true,
    hasstatus  => true,
    require    => Package['php5-fpm'],
  }

  if $servername == '' {
    $srvname = $name
  } else {
    $srvname = $servername
  }

  if $path == '' {
    $rootpath = "/var/www/${srvname}"
  } else {
    $rootpath = $path
  }

  # Try and work out what we're talking to on the other end of unicorn
  # If it's a bare path, put unix: before it, otherwise pass it
  # through. This means just files are assumed to be socket. If it's
  # something else (unix/http) all good, otherwise fail.
  case $fpm_socket {
    /^(unix|http?):/: { $fpm_upstream = regsubst( $fpm_socket, '^(http?://)(.+?)/?$', '\2' , 'I' ) }
    /^\//:            { $fpm_upstream = "unix:${fpm_socket}" }
    default:          { fail( "Value of ${fpm_socket} is unsupported.")}
  }

  # Need to make some variable names so the templates can use them!
  # Such as an app_server name that is unique, so when we have ssl and
  # non-ssl unicorn hosts they still work.
  if $ssl == true {
    $appname = regsubst( $srvname , '^(\w+?)\..*?$' , '\1_ssl' )
  } else {
    $appname = regsubst( $srvname , '^(\w+?)\..*?$' , '\1' )
  }

  if $ssl == true {
    include ssl::params
    $ssl_path = $ssl::params::ssl_path
  }


  file {
    "${nginx::params::vdir}/${priority}-${name}":
      content => template($template),
      owner   => 'root',
      group   => '0',
      mode    => '0755',
      require => Package['nginx'],
      notify  => Service['nginx'],
  }

  # liberally borrowed from apache module.
  if ! defined(Firewall["0100-INPUT ACCEPT ${port}"]) {
    @firewall {
      "0100-INPUT ACCEPT ${port}":
        jump  => 'ACCEPT',
        dport => $port,
        proto => 'tcp'
    }
  }

}
# EOF