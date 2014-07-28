#!/bin/sh /usr/share/centrifydc/perl/run

use strict;
use lib '/usr/share/centrifydc/perl';

use CentrifyDC::GP::Mapper;
use CentrifyDC::GP::GPIsolation qw(GetRegKey);

my $file;
my $action;
my $user;
$file = {
    'comment_markers' => [
      '#',
    ],
    'hierarchy_separator' => '.',
    'list_expr' => ', *| +',
    'list_separator' => ', ',
    'lock' => '/etc/centrifydc/centrifydc.conf.lock',
    'match_expr' => [
      '/^\s*([^\s:=]+)[:=]\s*(.*)/',
    ],
    'named_list_separator' => ',',
    'parent_expr' => '^(.*)\.([^\.]+)$',
    'path' => [
      '/etc/centrifydc/centrifydc.conf',
    ],
    'post_action' => [
      'DO_ADRELOAD',
    ],
    'value_map' => {
      'adclient.autoedit' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.autoedit',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adclient.autoedit.dsconfig' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.autoedit.dsconfig',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adclient.autoedit.methods' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.autoedit.methods',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adclient.autoedit.nscd' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.autoedit.nscd',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adclient.autoedit.nss' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.autoedit.nss',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adclient.autoedit.pam' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.autoedit.pam',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adclient.autoedit.pwgrd' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.autoedit.pwgrd',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adclient.autoedit.user' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.autoedit.user',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adclient.cache.cleanup.interval' => {
        'default_data' => '10',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.cache.cleanup.interval',
        'value_type' => 'named',
      },
      'adclient.cache.encrypt' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.cache.encrypt',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adclient.cache.encryption.type' => {
        'default_data' => 'arcfour-hmac-md5',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.cache.encryption.type',
        'value_type' => 'named',
      },
      'adclient.cache.expires' => {
        'default_data' => '3600',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.cache.expires',
        'value_type' => 'named',
      },
      'adclient.cache.expires.gc' => {
        'default_data' => '3600',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.cache.expires.gc',
        'value_type' => 'named',
      },
      'adclient.cache.expires.group' => {
        'default_data' => '3600',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.cache.expires.group',
        'value_type' => 'named',
      },
      'adclient.cache.expires.user' => {
        'default_data' => '3600',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.cache.expires.user',
        'value_type' => 'named',
      },
      'adclient.cache.negative.lifetime' => {
        'default_data' => '5',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.cache.negative.lifetime',
        'value_type' => 'named',
      },
      'adclient.client.idle.timeout' => {
        'default_data' => '900',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.client.idle.timeout',
        'value_type' => 'named',
      },
      'adclient.clients.threads' => {
        'default_data' => '4',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.clients.threads',
        'value_type' => 'named',
      },
      'adclient.clients.threads.max' => {
        'default_data' => '20',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.clients.threads.max',
        'value_type' => 'named',
      },
      'adclient.custom.attributes' => {
        'post_action' => [
          'DO_ADFLUSH',
        ],
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.custom.attributes',
        'value_type' => 'named',
      },
      'adclient.custom.attributes.computer' => {
        'post_action' => [
          'DO_ADFLUSH',
        ],
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.custom.attributes.computer',
        'value_type' => 'named',
      },
      'adclient.custom.attributes.group' => {
        'post_action' => [
          'DO_ADFLUSH',
        ],
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.custom.attributes.group',
        'value_type' => 'named',
      },
      'adclient.custom.attributes.user' => {
        'post_action' => [
          'DO_ADFLUSH',
        ],
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.custom.attributes.user',
        'value_type' => 'named',
      },
      'adclient.disk.check.free' => {
        'default_data' => '51200',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.disk.check.free',
        'value_type' => 'named',
      },
      'adclient.disk.check.interval' => {
        'default_data' => '5',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.disk.check.interval',
        'value_type' => 'named',
      },
      'adclient.dns.cache.size' => {
        'default_data' => '50',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.dns.cache.size',
        'value_type' => 'named',
      },
      'adclient.dns.cache.timeout' => {
        'default_data' => '300',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.dns.cache.timeout',
        'value_type' => 'named',
      },
      'adclient.dns.update.interval' => {
        'default_data' => '15',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.dns.update.interval',
        'value_type' => 'named',
      },
      'adclient.dumpcore' => {
        'default_data' => 'once',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.dumpcore',
        'value_type' => 'named',
      },
      'adclient.dzdo.clear.passwd.timestamp' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.dzdo.clear.passwd.timestamp',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adclient.fetch.object.count' => {
        'default_data' => '100',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.fetch.object.count',
        'value_type' => 'named',
      },
      'adclient.force.salt.lookup' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.force.salt.lookup',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adclient.hash.allow' => {
        'default_data' => '',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.hash.allow',
        'value_type' => 'named',
      },
      'adclient.hash.deny' => {
        'default_data' => '',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.hash.deny',
        'value_type' => 'named',
      },
      'adclient.hash.expires' => {
        'default_data' => '7',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.hash.expires',
        'value_type' => 'named',
      },
      'adclient.krb5.autoedit' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Kerberos',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.krb5.autoedit',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adclient.krb5.password.change.interval' => {
        'default_data' => '7',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Kerberos',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.krb5.password.change.interval',
        'value_type' => 'named',
      },
      'adclient.ldap.socket.timeout' => {
        'default_data' => '5',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.ldap.socket.timeout',
        'value_type' => 'named',
      },
      'adclient.ldap.timeout' => {
        'default_data' => '7',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.ldap.timeout',
        'value_type' => 'named',
      },
      'adclient.ldap.timeout.search' => {
        'default_data' => '14',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.ldap.timeout.search',
        'value_type' => 'named',
      },
      'adclient.ldap.trust.enabled' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.ldap.trust.enabled',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adclient.ldap.trust.timeout' => {
        'default_data' => '5',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.ldap.trust.timeout',
        'value_type' => 'named',
      },
      'adclient.local.group.merge' => {
        'default_data' => 'false',
        'post_action' => [
          'DO_ADFLUSH',
        ],
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.local.group.merge',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adclient.lrpc2.receive.timeout' => {
        'default_data' => '30',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.lrpc2.receive.timeout',
        'value_type' => 'named',
      },
      'adclient.lrpc2.send.timeout' => {
        'default_data' => '30',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.lrpc2.send.timeout',
        'value_type' => 'named',
      },
      'adclient.mac.map.home.to.users' => {
        'default_data' => 'false',
        'post_action' => [
          'DO_ADFLUSH',
        ],
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.mac.map.home.to.users',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adclient.prefer.cache.validation' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.prefer.cache.validation',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adclient.prevalidate.allow.groups' => {
        'default_data' => '',
        'named_list' => '1',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Prevalidation',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.prevalidate.allow.groups',
        'value_type' => 'named',
      },
      'adclient.prevalidate.allow.users' => {
        'default_data' => '',
        'named_list' => '1',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Prevalidation',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.prevalidate.allow.users',
        'value_type' => 'named',
      },
      'adclient.prevalidate.deny.groups' => {
        'default_data' => '',
        'named_list' => '1',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Prevalidation',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.prevalidate.deny.groups',
        'value_type' => 'named',
      },
      'adclient.prevalidate.deny.users' => {
        'default_data' => '',
        'named_list' => '1',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Prevalidation',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.prevalidate.deny.users',
        'value_type' => 'named',
      },
      'adclient.prevalidate.interval' => {
        'default_data' => '8',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Prevalidation',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.prevalidate.interval',
        'value_type' => 'named',
      },
      'adclient.prevalidate.service' => {
        'default_data' => 'preval',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Prevalidation',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.prevalidate.service',
        'value_type' => 'named',
      },
      'adclient.server.try.max' => {
        'default_data' => '0',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.server.try.max',
        'value_type' => 'named',
      },
      'adclient.sudo.clear.passwd.timestamp' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Sudo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.sudo.clear.passwd.timestamp',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adclient.udp.timeout' => {
        'default_data' => '15',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adclient.udp.timeout',
        'value_type' => 'named',
      },
      'adclient.use.all.cpus' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.use.all.cpus',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adclient.user.lookup.cn' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.user.lookup.cn',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adclient.user.lookup.display' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.user.lookup.display',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'adpasswd.account.disabled.mesg' => {
        'default_data' => 'Account cannot be accessed at this time.\\\\nPlease contact your system administrator',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adpasswd.account.disabled.mesg',
        'value_type' => 'named',
      },
      'adpasswd.account.invalid.mesg' => {
        'default_data' => 'Invalid username or password',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adpasswd.account.invalid.mesg',
        'value_type' => 'named',
      },
      'adpasswd.password.change.disabled.mesg' => {
        'default_data' => 'Password change for this user has been disabled in Active Directory',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adpasswd.password.change.disabled.mesg',
        'value_type' => 'named',
      },
      'adpasswd.password.change.perm.mesg' => {
        'default_data' => 'You do not have permission to change this users password.\\\\nPlease contact your system administrator.',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adpasswd.password.change.perm.mesg',
        'value_type' => 'named',
      },
      'adupdate.useradd.group.default' => {
        'default_data' => '10000',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Miscellaneous',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'adupdate.useradd.group.default',
        'value_type' => 'named',
      },
      'auto.schema.allow.groups' => {
        'advalue' => '1',
        'default_data' => '',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'auto.schema.allow.groups',
        'value_type' => 'named',
      },
      'auto.schema.allow.users' => {
        'advalue' => '1',
        'default_data' => '',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'auto.schema.allow.users',
        'value_type' => 'named',
      },
      'auto.schema.apple_scheme' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'auto.schema.apple_scheme',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'auto.schema.domain.prefix' => {
        'additive' => '1',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient/wsdomainprefixoverride',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => '',
        'value_type' => 'all',
      },
      'auto.schema.groups' => {
        'advalue' => '1',
        'default_data' => '',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'auto.schema.groups',
        'value_type' => 'named',
      },
      'auto.schema.homedir' => {
        'default_data' => '/Users/%{user}',
        'post_action' => [
          'DO_ADFLUSH',
        ],
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'auto.schema.homedir',
        'value_type' => 'named',
      },
      'auto.schema.primary.gid' => {
        'default_data' => '20',
        'post_action' => [
          'DO_ADFLUSH',
        ],
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'auto.schema.primary.gid',
        'value_type' => 'named',
      },
      'auto.schema.remote.file.service' => {
        'default_data' => 'SMB',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'auto.schema.remote.file.service',
        'value_type' => 'named',
      },
      'auto.schema.shell' => {
        'default_data' => '/bin/bash',
        'post_action' => [
          'DO_ADFLUSH',
        ],
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'auto.schema.shell',
        'value_type' => 'named',
      },
      'auto.schema.use.adhomedir' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Adclient',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'auto.schema.use.adhomedir',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'dns.block' => {
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/BlockDNS',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dns.block',
        'value_type' => 'named',
      },
      'dns.cache.timeout' => {
        'default_data' => '300',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'dns.cache.timeout',
        'value_type' => 'named',
      },
      'dns.dc' => {
        'additive' => '1',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/dnsoverridedc',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => '',
        'value_type' => 'all',
      },
      'dns.forcetcp' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dns.forcetcp',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'dns.gc' => {
        'additive' => '1',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/dnsoverridegc',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => '',
        'value_type' => 'all',
      },
      'dns.max.udp.packet' => {
        'default_data' => '4096',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'dns.max.udp.packet',
        'value_type' => 'named',
      },
      'dns.rotate' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dns.rotate',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'dzdo.always_set_home' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dzdo.always_set_home',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'dzdo.badpass_message' => {
        'default_data' => 'Sorry, try again.',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dzdo.badpass_message',
        'value_type' => 'named',
      },
      'dzdo.env_check' => {
        'default_data' => '',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dzdo.env_check',
        'value_type' => 'named',
      },
      'dzdo.env_delete' => {
        'default_data' => '',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dzdo.env_delete',
        'value_type' => 'named',
      },
      'dzdo.env_keep' => {
        'default_data' => '',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dzdo.env_keep',
        'value_type' => 'named',
      },
      'dzdo.lecture' => {
        'default_data' => 'once',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dzdo.lecture',
        'value_type' => 'named',
      },
      'dzdo.lecture_file' => {
        'default_data' => '',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dzdo.lecture_file',
        'value_type' => 'named',
      },
      'dzdo.log_good' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dzdo.log_good',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'dzdo.passprompt' => {
        'default_data' => '[dzdo] password for %p:',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dzdo.passprompt',
        'value_type' => 'named',
      },
      'dzdo.passwd_timeout' => {
        'default_data' => '5',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'dzdo.passwd_timeout',
        'value_type' => 'named',
      },
      'dzdo.path_info' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dzdo.path_info',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'dzdo.search_path' => {
        'default_data' => 'file:/etc/centrifydc/dzdo.search_path',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dzdo.search_path',
        'value_type' => 'named',
      },
      'dzdo.secure_path' => {
        'default_data' => 'file:/etc/centrifydc/dzdo.secure_path',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dzdo.secure_path',
        'value_type' => 'named',
      },
      'dzdo.set.runas.explicit' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dzdo.set.runas.explicit',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'dzdo.set_home' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dzdo.set_home',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'dzdo.timestamp_timeout' => {
        'default_data' => '5',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'dzdo.timestamp_timeout',
        'value_type' => 'named',
      },
      'dzdo.timestampdir' => {
        'default_data' => '/var/run/dzdo',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dzdo.timestampdir',
        'value_type' => 'named',
      },
      'dzdo.tty_tickets' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dzdo.tty_tickets',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'dzdo.use.realpath' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dzdo.use.realpath',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'dzdo.validator' => {
        'default_data' => '/usr/share/centrifydc/sbin/dzcheck',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dzdo.validator',
        'value_type' => 'named',
      },
      'dzdo.validator.required' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Dzdo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'dzdo.validator.required',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'gp.disable.user' => {
        'default_data' => 'true',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/GP',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'gp.disable.user',
        'value_type' => 'named',
        'valueoff' => 'true',
        'valueon' => 'false',
      },
      'gp.mappers.machine' => {
        'default_data' => '*',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/GP',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'gp.mappers.machine',
        'value_type' => 'named',
      },
      'gp.mappers.timeout' => {
        'default_data' => '30',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/GP',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'gp.mappers.timeout',
        'value_type' => 'named',
      },
      'gp.mappers.timeout.all' => {
        'default_data' => '240',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/GP',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'gp.mappers.timeout.all',
        'value_type' => 'named',
      },
      'gp.mappers.user' => {
        'default_data' => '*',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/GP',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'gp.mappers.user',
        'value_type' => 'named',
      },
      'krb5.cache.infinite.renewal' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Kerberos',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'krb5.cache.infinite.renewal',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'krb5.cache.renew.interval' => {
        'default_data' => '8',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Kerberos',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'krb5.cache.renew.interval',
        'value_type' => 'named',
      },
      'krb5.cache.type' => {
        'default_data' => 'FILE',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Kerberos',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'krb5.cache.type',
        'value_type' => 'named',
      },
      'krb5.config.update' => {
        'default_data' => '8',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Kerberos',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'krb5.config.update',
        'value_type' => 'named',
      },
      'krb5.forcetcp' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Kerberos',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'krb5.forcetcp',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'krb5.forwardable.user.tickets' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Kerberos',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'krb5.forwardable.user.tickets',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'krb5.generate.kvno' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Kerberos',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'krb5.generate.kvno',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'krb5.udp.preference.limit' => {
        'default_data' => '1465',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Kerberos',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'krb5.udp.preference.limit',
        'value_type' => 'named',
      },
      'krb5.use.dns.lookup.kdc' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Kerberos',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'krb5.use.dns.lookup.kdc',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'krb5.use.dns.lookup.realm' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Kerberos',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'krb5.use.dns.lookup.realm',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'krb5.use.kdc.timesync' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Kerberos',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'krb5.use.kdc.timesync',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'logger.facility.*' => {
        'default_data' => 'auth',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Logging',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'logger.facility.*',
        'value_type' => 'named',
      },
      'logger.facility.adclient' => {
        'default_data' => 'auth',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Logging',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'logger.facility.adclient',
        'value_type' => 'named',
      },
      'logger.facility.adnisd' => {
        'default_data' => 'auth',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Logging',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'logger.facility.adnisd',
        'value_type' => 'named',
      },
      'logger.queue.size' => {
        'default_data' => '256',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Logging',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'logger.queue.size',
        'value_type' => 'named',
      },
      'lrpc.timeout' => {
        'default_data' => '300',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'lrpc.timeout',
        'value_type' => 'named',
      },
      'mac.network.autoedit.mdns_timeout' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Mac/Network',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'mac.network.autoedit.mdns_timeout',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'mac.network.mdns_timeout' => {
        'default_data' => '1',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Mac/Network',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'mac.network.mdns_timeout',
        'value_type' => 'named',
      },
      'nisd.domain.name' => {
        'default_data' => 'default',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/nis',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'nisd.domain.name',
        'value_type' => 'named',
      },
      'nisd.exclude.maps' => {
        'default_data' => 'netid services',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/nis',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'nisd.exclude.maps',
        'value_type' => 'named',
      },
      'nisd.largegroup.name.length' => {
        'default_data' => '1024',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/nis',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'nisd.largegroup.name.length',
        'value_type' => 'named',
      },
      'nisd.largegroup.suffix' => {
        'default_data' => '',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/nis',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'nisd.largegroup.suffix',
        'value_type' => 'named',
      },
      'nisd.maps' => {
        'default_data' => 'passwd group hosts',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/nis',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'nisd.maps',
        'value_type' => 'named',
      },
      'nisd.maps.max' => {
        'default_data' => '1024',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/nis',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'nisd.maps.max',
        'value_type' => 'named',
      },
      'nisd.securenets' => {
        'default_data' => '0/0',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/nis',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'nisd.securenets',
        'value_type' => 'named',
      },
      'nisd.server.switch.delay' => {
        'default_data' => '600',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/nis',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'nisd.server.switch.delay',
        'value_type' => 'named',
      },
      'nisd.startup.delay' => {
        'default_data' => '180',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/nis',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'nisd.startup.delay',
        'value_type' => 'named',
      },
      'nisd.threads' => {
        'default_data' => '4',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/nis',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'nisd.threads',
        'value_type' => 'named',
      },
      'nisd.update.interval' => {
        'default_data' => '1800',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/nis',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'nisd.update.interval',
        'value_type' => 'named',
      },
      'nss.group.ignore' => {
        'default_data' => 'file:/etc/centrifydc/group.ignore',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Login',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'nss.group.ignore',
        'value_type' => 'named',
      },
      'nss.group.override' => {
        'default_data' => 'file:/etc/centrifydc/group.ovr',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/NSSOverrides/Group',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'nss.group.override',
        'value_type' => 'named',
      },
      'nss.mingid' => {
        'default_data' => '0',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Login',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'nss.mingid',
        'value_type' => 'named',
      },
      'nss.minuid' => {
        'default_data' => '0',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Login',
        'reg_type' => [
          'REG_DWORD',
        ],
        'reg_value' => 'nss.minuid',
        'value_type' => 'named',
      },
      'nss.passwd.override' => {
        'default_data' => 'file:/etc/centrifydc/passwd.ovr',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/NSSOverrides/Passwd',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'nss.passwd.override',
        'value_type' => 'named',
      },
      'nss.squash.root' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/NSSRootUser',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'nss.squash.root',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'nss.user.ignore' => {
        'default_data' => 'file:/etc/centrifydc/user.ignore',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Login',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'nss.user.ignore',
        'value_type' => 'named',
      },
      'pam.account.conflict.both.mesg' => {
        'default_data' => 'Accounts with conflicting name (%s) and UID (%d) exist locally',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Pam',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.account.conflict.both.mesg',
        'value_type' => 'named',
      },
      'pam.account.conflict.name.mesg' => {
        'default_data' => 'Account with conflicting name (%s) exists locally',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Pam',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.account.conflict.name.mesg',
        'value_type' => 'named',
      },
      'pam.account.conflict.uid.mesg' => {
        'default_data' => 'Account with conflicting UID (%d) exists locally',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Pam',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.account.conflict.uid.mesg',
        'value_type' => 'named',
      },
      'pam.account.disabled.mesg' => {
        'default_data' => 'Account cannot be accessed at this time.\\\\nPlease contact your system administrator.',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.account.disabled.mesg',
        'value_type' => 'named',
      },
      'pam.account.expired.mesg' => {
        'default_data' => 'Account cannot be accessed at this time.\\\\nPlease contact your system administrator.',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.account.expired.mesg',
        'value_type' => 'named',
      },
      'pam.account.locked.mesg' => {
        'default_data' => 'Account Locked',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.account.locked.mesg',
        'value_type' => 'named',
      },
      'pam.adclient.down.mesg' => {
        'default_data' => '(Unable to reach Active Directory - using local account)',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.adclient.down.mesg',
        'value_type' => 'named',
      },
      'pam.allow.groups' => {
        'active' => '$value_map->{pam_hidden_allow_or_deny}{reg_data} ne "deny"',
        'data_value' => 'pam_hidden_groups',
        'named_list' => '1',
        'post_action' => [
          'DO_ADFLUSH',
        ],
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Login',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.allow.groups',
        'value_type' => 'named',
      },
      'pam.allow.override' => {
        'default_data' => 'root',
        'post_action' => [
          'DO_ADFLUSH',
        ],
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Login',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.allow.override',
        'value_type' => 'named',
      },
      'pam.allow.users' => {
        'active' => '$value_map->{pam_hidden_allow_or_deny}{reg_data} ne "deny"',
        'data_value' => 'pam_hidden_users',
        'named_list' => '1',
        'post_action' => [
          'DO_ADFLUSH',
        ],
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Login',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.allow.users',
        'value_type' => 'named',
      },
      'pam.auth.create.krb5.cache' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Kerberos',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.auth.create.krb5.cache',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'pam.auth.failure.mesg' => {
        'default_data' => 'Password authentication failure',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.auth.failure.mesg',
        'value_type' => 'named',
      },
      'pam.create.k5login' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Pam',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.create.k5login',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'pam.deny.groups' => {
        'active' => '$value_map->{pam_hidden_allow_or_deny}{reg_data} ne "allow"',
        'data_value' => 'pam_hidden_groups',
        'named_list' => '1',
        'post_action' => [
          'DO_ADFLUSH',
        ],
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Login',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.deny.groups',
        'value_type' => 'named',
      },
      'pam.deny.users' => {
        'active' => '$value_map->{pam_hidden_allow_or_deny}{reg_data} ne "allow"',
        'data_value' => 'pam_hidden_users',
        'named_list' => '1',
        'post_action' => [
          'DO_ADFLUSH',
        ],
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Login',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.deny.users',
        'value_type' => 'named',
      },
      'pam.homedir.create' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Pam',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.homedir.create',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'pam.homedir.create.mesg' => {
        'default_data' => 'Creating home directory ...',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Pam',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.homedir.create.mesg',
        'value_type' => 'named',
      },
      'pam.mapuser' => {
        'additive' => '1',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/UserMap',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => '',
        'value_type' => 'all',
      },
      'pam.password.change.mesg' => {
        'default_data' => 'Changing Active Directory password for ',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.password.change.mesg',
        'value_type' => 'named',
      },
      'pam.password.change.required.mesg' => {
        'default_data' => 'You are required to change your password immediately',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.password.change.required.mesg',
        'value_type' => 'named',
      },
      'pam.password.confirm.mesg' => {
        'default_data' => 'Confirm new Active Directory password: ',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.password.confirm.mesg',
        'value_type' => 'named',
      },
      'pam.password.empty.mesg' => {
        'default_data' => 'Empty password not allowed',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.password.empty.mesg',
        'value_type' => 'named',
      },
      'pam.password.enter.mesg' => {
        'default_data' => 'Password: ',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.password.enter.mesg',
        'value_type' => 'named',
      },
      'pam.password.expiry.warn.mesg' => {
        'default_data' => 'Password will expire in %d days',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.password.expiry.warn.mesg',
        'value_type' => 'named',
      },
      'pam.password.new.mesg' => {
        'default_data' => 'Enter new Active Directory password: ',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.password.new.mesg',
        'value_type' => 'named',
      },
      'pam.password.new.mismatch.mesg' => {
        'default_data' => 'New passwords don\'t match',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.password.new.mismatch.mesg',
        'value_type' => 'named',
      },
      'pam.password.old.mesg' => {
        'default_data' => '(current) Active Directory password: ',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.password.old.mesg',
        'value_type' => 'named',
      },
      'pam.policy.violation.mesg' => {
        'default_data' => 'The password change operation failed due to a policy restriction set by the\\\\nActive Directory administrator. This may be due to the new password length,\\\\nlack of complexity or a minimum age for the current password.',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.policy.violation.mesg',
        'value_type' => 'named',
      },
      'pam.sync.mapuser' => {
        'default_data' => '',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Login',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.sync.mapuser',
        'value_type' => 'named',
      },
      'pam.uid.conflict' => {
        'default_data' => 'warn',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Pam',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.uid.conflict',
        'value_type' => 'named',
      },
      'pam.workstation.denied.mesg' => {
        'default_data' => 'Your account is configured to prevent you from using this computer.\\\\nPlease try another computer.',
        'file_data_expr' => [
          '$data =~ s/\\\\ $/ /',
        ],
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data =~ s/ $/\\\\ /',
        ],
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/PasswordPrompt',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.workstation.denied.mesg',
        'value_type' => 'named',
      },
      'pam_hidden_allow_or_deny' => {
        'active' => '0',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Login',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam_hidden_allow_or_deny',
        'value_type' => 'named',
      },
      'pam_hidden_groups' => {
        'active' => '0',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Login',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam_hidden_groups',
        'value_type' => 'named',
      },
      'pam_hidden_users' => {
        'active' => '0',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Login',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam_hidden_users',
        'value_type' => 'named',
      },
      'secedit.system.access.lockout.allowofflinelogin' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Login',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'secedit.system.access.lockout.allowofflinelogin',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
    },
    'write_data' => '$value: $data\n',
};

$action = $ARGV[0];
my $mode = $ARGV[2] ? $ARGV[2] : $ARGV[1];
$user = $ARGV[2] ? $ARGV[1] : undef;

if ($action eq "unmap")
{

    CentrifyDC::GP::Mapper::UnMap($file, $user);
}
else
{
    CentrifyDC::GP::Mapper::Map($file, $user);
}
