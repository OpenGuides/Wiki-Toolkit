package CGI::Wiki::Setup::MySQL;

use strict;

use vars qw( @ISA $VERSION );

use CGI::Wiki::Setup::Database;

@ISA = qw( CGI::Wiki::Setup::Database );
$VERSION = '0.09';

use DBI;
use Carp;

my %create_sql = (
	schema_info => [ qq|
CREATE TABLE schema_info (
  version   int(10)      NOT NULL default 0
)
|, qq|
INSERT INTO schema_info VALUES (|.($VERSION*100).qq|)
| ],

    node => [ qq|
CREATE TABLE node (
  id        integer      NOT NULL AUTO_INCREMENT,
  name      varchar(200) NOT NULL DEFAULT '',
  version   int(10)      NOT NULL default 0,
  text      mediumtext   NOT NULL default '',
  modified  datetime     default NULL,
  moderate  bool         NOT NULL default '0',
  PRIMARY KEY (id)
)
| ],

    content => [ qq|
CREATE TABLE content (
  node_id   integer      NOT NULL,
  version   int(10)      NOT NULL default 0,
  text      mediumtext   NOT NULL default '',
  modified  datetime     default NULL,
  comment   mediumtext   NOT NULL default '',
  moderated bool         NOT NULL default '1',
  PRIMARY KEY (node_id, version)
)
| ],
    internal_links => [ qq|
CREATE TABLE internal_links (
  link_from varchar(200) NOT NULL default '',
  link_to   varchar(200) NOT NULL default '',
  PRIMARY KEY (link_from, link_to)
)
| ],
    metadata => [ qq|
CREATE TABLE metadata (
  node_id        integer      NOT NULL,
  version        int(10)      NOT NULL default 0,
  metadata_type  varchar(200) NOT NULL DEFAULT '',
  metadata_value mediumtext   NOT NULL DEFAULT ''
)
|, qq|
CREATE INDEX metadata_index ON metadata(node_id, version, metadata_type, metadata_value(10))
| ]
);

=head1 NAME

CGI::Wiki::Setup::MySQL - Set up tables for a CGI::Wiki store in a MySQL database.

=head1 SYNOPSIS

  use CGI::Wiki::Setup::MySQL;
  CGI::Wiki::Setup::MySQL::setup($dbname, $dbuser, $dbpass, $dbhost);

Omit $dbhost if the database is local.

=head1 DESCRIPTION

Set up a MySQL database for use as a CGI::Wiki store.

=head1 FUNCIONS

=over 4

=item B<setup>

  use CGI::Wiki::Setup::MySQL;
  CGI::Wiki::Setup::MySQL::setup($dbname, $dbuser, $dbpass, $dbhost);

or

  CGI::Wiki::Setup::Mysql::setup( $dbh );

You can either provide an active database handle C<$dbh> or connection
parameters.                                                                    

If you provide connection parameters the following arguments are
mandatory -- the database name, the username and the password. The
username must be able to create and drop tables in the database.

The $dbhost argument is optional -- omit it if the database is local.

B<NOTE:> If a table that the module wants to create already exists,
C<setup> will leave it alone. This means that you can safely run this
on an existing L<CGI::Wiki> database to bring the schema up to date
with the current L<CGI::Wiki> version. If you wish to completely start
again with a fresh database, run C<cleardb> first.

=cut

sub setup {
    my @args = @_;
    my $dbh = _get_dbh( @args );
    my $disconnect_required = _disconnect_required( @args );

    # Check whether tables exist
    my $sth = $dbh->prepare("SHOW TABLES") or croak $dbh->errstr;
    $sth->execute;
    my %tables;
    while ( my $table = $sth->fetchrow_array ) {
        $tables{$table} = 1;
    }

	# Do we need to upgrade the schema of existing tables?
	# (Don't check if no tables currently exist)
	my $upgrade_schema;
	my @cur_data;
	if(scalar keys %tables > 0) {
		$upgrade_schema = CGI::Wiki::Setup::Database::get_database_upgrade_required($dbh,$VERSION);
	}
	if($upgrade_schema) {
		# Grab current data
		print "Upgrading: $upgrade_schema\n";
		@cur_data = eval("&CGI::Wiki::Setup::Database::fetch_upgrade_".$upgrade_schema."(\$dbh)");

		# Drop the current tables
		cleardb($dbh);
	}

	# Set up tables if not found
    foreach my $required ( keys %create_sql ) {
        if ( $tables{$required} ) {
            print "Table $required already exists... skipping...\n";
        } else {
            print "Creating table $required... done\n";
            foreach my $sql ( @{ $create_sql{$required} } ) {
                $dbh->do($sql) or croak $dbh->errstr;
            }
        }
    }

	# If upgrading, load in the new data
	if($upgrade_schema) {
		CGI::Wiki::Setup::Database::bulk_data_insert($dbh,@cur_data);
	}

    # Clean up if we made our own dbh.
    $dbh->disconnect if $disconnect_required;
}

=item B<cleardb>

  use CGI::Wiki::Setup::MySQL;

  # Clear out all CGI::Wiki tables from the database.
  CGI::Wiki::Setup::MySQL::cleardb($dbname, $dbuser, $dbpass, $dbhost);

or

  CGI::Wiki::Setup::Mysql::cleardb( $dbh );

You can either provide an active database handle C<$dbh> or connection
parameters.                                                                    

If you provide connection parameters the following arguments are
mandatory -- the database name, the username and the password. The
username must be able to drop tables in the database.

The $dbhost argument is optional -- omit if the database is local.

Clears out all L<CGI::Wiki> store tables from the database. B<NOTE>
that this will lose all your data; you probably only want to use this
for testing purposes or if you really screwed up somewhere. Note also
that it doesn't touch any L<CGI::Wiki> search backend tables; if you
have any of those in the same or a different database see either
L<CGI::Wiki::Setup::DBIxFTS> or L<CGI::Wiki::Setup::SII>, depending on
which search backend you're using.

=cut

sub cleardb {
    my @args = @_;
    my $dbh = _get_dbh( @args );
    my $disconnect_required = _disconnect_required( @args );

    print "Dropping tables... ";
    $dbh->do("DROP TABLE IF EXISTS " . join( ",", keys %create_sql ) )
      or croak $dbh->errstr;
    print "done\n";

    # Clean up if we made our own dbh.
    $dbh->disconnect if $disconnect_required;
}

sub _get_dbh {
    # Database handle passed in.
    if ( ref $_[0] and ref $_[0] eq 'DBI::db' ) {
        return $_[0];
    }

    # Args passed as hashref.
    if ( ref $_[0] and ref $_[0] eq 'HASH' ) {
        my %args = %{$_[0]};
        if ( $args{dbh} ) {
            return $args{dbh};
	} else {
            return _make_dbh( %args );
        }
    }

    # Args passed as list of connection details.
    return _make_dbh(
                      dbname => $_[0],
                      dbuser => $_[1],
                      dbpass => $_[2],
                      dbhost => $_[3],
                    );
}

sub _disconnect_required {
    # Database handle passed in.
    if ( ref $_[0] and ref $_[0] eq 'DBI::db' ) {
        return 0;
    }

    # Args passed as hashref.
    if ( ref $_[0] and ref $_[0] eq 'HASH' ) {
        my %args = %{$_[0]};
        if ( $args{dbh} ) {
            return 0;
	} else {
            return 1;
        }
    }

    # Args passed as list of connection details.
    return 1;
}

sub _make_dbh {
    my %args = @_;
    my $dsn = "dbi:mysql:$args{dbname}";
    $dsn .= ";host=$args{dbhost}" if $args{dbhost};
    my $dbh = DBI->connect($dsn, $args{dbuser}, $args{dbpass},
			   { PrintError => 1, RaiseError => 1,
			     AutoCommit => 1 } )
      or croak DBI::errstr;
    return $dbh;
}

=back

=head1 ALTERNATIVE CALLING SYNTAX

As requested by Podmaster.  Instead of passing arguments to the methods as

  ($dbname, $dbuser, $dbpass, $dbhost)

you can pass them as

  ( { dbname => $dbname,
      dbuser => $dbuser,
      dbpass => $dbpass,
      dbhost => $dbhost
    }
  )

or indeed as

  ( { dbh => $dbh } )

Note that's a hashref, not a hash.

=head1 AUTHOR

Kake Pugh (kake@earth.li).

=head1 COPYRIGHT

     Copyright (C) 2002-2004 Kake Pugh.  All Rights Reserved.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<CGI::Wiki>, L<CGI::Wiki::Setup::DBIxMySQL>, L<CGI::Wiki::Setup::SII>

=cut

1;

