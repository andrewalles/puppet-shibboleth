# Currently this only creates a _single_ metadata provider
# it will need to be modified to permit multiple metadata providers
define shibboleth::metadata(
  $provider_uri,
  $cert_uri                 = undef,
  $backing_file_dir         = $::shibboleth::conf_dir,
  $backing_file_name        = "${name}.xml",
  $cert_dir                 = $::shibboleth::conf_dir,
  $cert_file_name           = undef,
  $provider_type            = 'XML',
  $provider_reload_interval = '7200',
  $custom_xml               = undef,
  $metadata_filter_max_validity_interval  = '2419200'
){

  $backing_file = "${backing_file_dir}/${backing_file_name}"

  if $cert_uri {
    # Get the Metadata signing certificate
    exec{"get_${name}_metadata_cert":
      path    => ['/usr/bin'],
      command => "wget ${cert_uri} -O ${cert_file}",
      creates => $cert_file,
      notify  => Service['httpd','shibd'],
      before  => Augeas["shib_${name}_create_metadata_provider"]
    }

    $_cert_file_name = pick($cert_filename, inline_template("<%= @cert_uri.split('/').last  %>"))
    $cert_file    = "${cert_dir}/${_cert_file_name}"
    $aug_signature = [
      'set MetadataProvider/MetadataFilter[2]/#attribute/type Signature',
      "set MetadataProvider/MetadataFilter[2]/#attribute/certificate ${cert_file}",
    ]
  } else {"
    $aug_signature = 'rm MetadataProvider/MetadataFilter[2]/#attribute/type Signature'
  }

  if $metadata_filter_max_validity_interval > 0 {
    $aug_valid_until = [
      'set MetadataProvider/MetadataFilter[1]/#attribute/type RequireValidUntil',
      "set MetadataProvider/MetadataFilter[1]/#attribute/maxValidityInterval ${metadata_filter_max_validity_interval}",
    ]
  } else {
    $aug_valid_until = 'rm MetadataProvider/MetadataFilter[1]/#attribute/type RequireValidUntil'
  }

  # This puts the MetadataProvider entry in the 'right' place
  augeas{"shib_${name}_create_metadata_provider":
    lens    => 'Xml.lns',
    incl    => $::shibboleth::config_file,
    context => "/files${::shibboleth::config_file}/SPConfig/ApplicationDefaults",
    changes => [
      'ins MetadataProvider after Errors',
    ],
    onlyif  => 'match MetadataProvider/#attribute/uri size == 0',
    notify  => Service['httpd','shibd'],
  }

  # This will update the attributes and child nodes if they change
  augeas{"shib_${name}_metadata_provider":
    lens    => 'Xml.lns',
    incl    => $::shibboleth::config_file,
    context => "/files${::shibboleth::config_file}/SPConfig/ApplicationDefaults",
    changes => flatten([
      "set MetadataProvider/#attribute/type ${provider_type}",
      "set MetadataProvider/#attribute/uri ${provider_uri}",
      "set MetadataProvider/#attribute/backingFilePath ${backing_file}",
      "set MetadataProvider/#attribute/reloadInterval ${provider_reload_interval}",
      $aug_valid_until,
      $aug_signature,
    ]),
    notify  => Service['httpd','shibd'],
    require => [Augeas["shib_${name}_create_metadata_provider"]],
  }

}
