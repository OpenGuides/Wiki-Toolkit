package CGI::Wiki::Store::Database;

use strict;

use vars qw( $VERSION $timestamp_fmt );
$timestamp_fmt = "%Y-%m-%d %H:%M:%S";

use DBI;
use Time::Piece;
use Time::Seconds;
use Carp qw( carp croak );
use Digest::MD5 qw( md5_hex );

$VERSION = '0.20';

=head1 NAME

CGI::Wiki::Store::Database - parent class for database storage backends
for CGI::Wiki

=head1 SYNOPSIS

Can't see yet why you'd want to use the backends directly, but:

  # See below for parameter details.
  my $store = CGI::Wiki::Store::MySQL->new( %config );

=head1 METHODS

=over 4

=item B<new>

  my $store = CGI::Wiki::Store::MySQL->new( dbname => "wiki",
					    dbuser => "wiki",
					    dbpass => "wiki",
                                            dbhost => "db.example.com" );

C<dbname> is mandatory. C<dbpass>, C<dbuser> and C<dbhost> are optional, but
you'll want to supply them unless your database's authentication
method doesn't require it.

=cut

sub new {
    my ($class, @args) = @_;
    my $self = {};
    bless $self, $class;
    return $self->_init(@args);
}

sub _init {
    my ($self, %args) = @_;

    # Store parameters.
    foreach ( qw(dbname) ) {
        die "Must supply a value for $_" unless defined $args{$_};
        $self->{"_$_"} = $args{$_};
    }
    $self->{_dbuser} = $args{dbuser} || "";
    $self->{_dbpass} = $args{dbpass} || "";
    $self->{_dbhost} = $args{dbhost} || "";

    # Connect to database and store the database handle.
    my ($dbname, $dbuser, $dbpass, $dbhost) =
                               @$self{qw(_dbname _dbuser _dbpass _dbhost)};
    my $dsn = $self->_dsn($dbname, $dbhost)
       or croak "No data source string provided by class";
    $self->{_dbh} = DBI->connect($dsn, $dbuser, $dbpass,
				 { PrintError => 0, RaiseError => 1,
				   AutoCommit => 1 } )
       or croak "Can't connect to database $dbname using $dsn: " . DBI->errstr;

    return $self;
}


=item B<retrieve_node>

  my $content = $store->retrieve_node($node);

  # Or get additional meta-data too.
  my %node = $store->retrieve_node("HomePage");
  print "Current Version: " . $node{version};

  # Maybe we stored some metadata too.
  my $categories = $node{metadata}{category};
  print "Categories: " . join(", ", @$categories);
  print "Postcode: $node{metadata}{postcode}[0]";

  # Or get an earlier version:
  my %node = $store->retrieve_node(name    => "HomePage",
			             version => 2 );
  print $node{content};


In scalar context, returns the current (raw Wiki language) contents of
the specified node. In list context, returns a hash containing the
contents of the node plus additional data:

=over 4

=item B<last_modified>

=item B<version>

=item B<checksum>

=item B<metadata> - a reference to a hash containing any caller-supplied
metadata sent along the last time the node was written

The node parameter is mandatory. The version parameter is optional and
defaults to the newest version. If the node hasn't been created yet,
it is considered to exist but be empty (this behaviour might change).

B<Note> on metadata - each hash value is returned as an array ref,
even if that type of metadata only has one value.

=cut

sub retrieve_node {
    my $self = shift;
    my %args = scalar @_ == 1 ? ( name => $_[0] ) : @_;
    # Note _retrieve_node_data is sensitive to calling context.
    return $self->_retrieve_node_data( %args ) unless wantarray;
    my %data = $self->_retrieve_node_data( %args );
    $data{checksum} = $self->_checksum(%data);
    return %data;
}

# Returns hash or scalar depending on calling context.
sub _retrieve_node_data {
    my ($self, %args) = @_;
    my %data = $self->_retrieve_node_content( %args );
    return $data{content} unless wantarray;

    # If we want additional data then get it.  Note that $data{version}
    # will already have been set by C<_retrieve_node_content>, if it wasn't
    # specified in the call.
    my $dbh = $self->dbh;
    my $sql = "SELECT metadata_type, metadata_value FROM metadata WHERE "
         . "node=" . $dbh->quote($args{name}) . " AND "
         . "version=" . $dbh->quote($data{version});
    my $sth = $dbh->prepare($sql);
    $sth->execute or croak $dbh->errstr;
    my %metadata;
    while ( my ($type, $val) = $sth->fetchrow_array ) {
        if ( defined $metadata{$type} ) {
	    push @{$metadata{$type}}, $val;
	} else {
            $metadata{$type} = [ $val ];
        }
    }
    $data{metadata} = \%metadata;
    return %data;
}

# $store->_retrieve_node_content( name    => $node_name,
#                                 version => $node_version );
# Params: 'name' is compulsory, 'version' is optional and defaults to latest.
# Returns a hash of data for C<retrieve_node> - content, version, last modified
sub _retrieve_node_content {
    my ($self, %args) = @_;
    croak "No valid node name supplied" unless $args{name};
    my $dbh = $self->dbh;
    my $sql;
    if ( $args{version} ) {
        $sql = "SELECT text, version, modified FROM content"
             . " WHERE  name=" . $dbh->quote($args{name})
             . " AND version=" . $dbh->quote($args{version});
    } else {
        $sql = "SELECT text, version, modified FROM node
                WHERE name=" . $dbh->quote($args{name});
    }
    my @results = $dbh->selectrow_array($sql);
    @results = ("", 0, "") unless scalar @results;
    my %data;
    @data{ qw( content version last_modified ) } = @results;
    return %data;
}

# Expects a hash as returned by ->retrieve_node
sub _checksum {
    my ($self, %node_data) = @_;
    my $string = $node_data{content};
    my %metadata = %{ $node_data{metadata} || {} };
    foreach my $key ( sort keys %metadata ) {
        $string .= "\0\0\0" . $key . "\0\0"
                 . join("\0", sort @{$metadata{$key}} );
    }
    return md5_hex($string);
}

# Expects an array of hashes whose keys and values are scalars.
sub _checksum_hashes {
    my ($self, @hashes) = @_;
    my @strings = "";
    foreach my $hashref ( @hashes ) {
        my %hash = %$hashref;
        my $substring = "";
        foreach my $key ( sort keys %hash ) {
            $substring .= "\0\0" . $key . "\0" . $hash{$key};
        }
        push @strings, $substring;
    }
    my $string = join("\0\0\0", sort @strings);
    return md5_hex($string);
}

=item B<node_exists>

  if ( $store->node_exists( "Wombat Defenestration" ) {
      # do something about the weird people infesting your wiki
  } else {
      # ah, safe, no weirdos here
  }

Returns true if the node has ever been created (even if it is
currently empty), and false otherwise.

=cut

sub node_exists {
    my ( $self, $node ) = @_;
    my %data = $self->retrieve_node($node) or return ();
    return $data{version}; # will be 0 if node doesn't exist, >=1 otherwise
}

=item B<verify_checksum>

  my $ok = $store->verify_checksum($node, $checksum);

Sees whether your checksum is current for the given node. Returns true
if so, false if not.

B<NOTE:> Be aware that when called directly and without locking, this
might not be accurate, since there is a small window between the
checking and the returning where the node might be changed, so
B<don't> rely on it for safe commits; use C<write_node> for that. It
can however be useful when previewing edits, for example.

=cut

sub verify_checksum {
    my ($self, $node, $checksum) = @_;
#warn $self;
    my %node_data = $self->_retrieve_node_data( name => $node );
    return ( $checksum eq $self->_checksum( %node_data ) );
}

=item B<list_backlinks>

  # List all nodes that link to the Home Page.
  my @links = $store->list_backlinks( node => "Home Page" );

=cut

sub list_backlinks {
    my ( $self, %args ) = @_;
    my $node = $args{node};
    croak "Must supply a node name" unless $node;
    my $dbh = $self->dbh;
    my $sql = "SELECT link_from FROM internal_links WHERE link_to="
            . $dbh->quote($node);
    my $sth = $dbh->prepare($sql);
    $sth->execute or croak $dbh->errstr;
    my @backlinks;
    while ( my $backlink = $sth->fetchrow_array ) {
        push @backlinks, $backlink;
    }
    return @backlinks;
}

=item B<list_dangling_links>

  # List all nodes that have been linked to from other nodes but don't
  # yet exist.
  my @links = $store->list_dangling_links;

Each node is returned once only, regardless of how many other nodes
link to it.

=cut

sub list_dangling_links {
    my $self = shift;
    my $dbh = $self->dbh;
    my $sql = "SELECT DISTINCT internal_links.link_to
               FROM internal_links LEFT JOIN node
                                   ON node.name=internal_links.link_to
               WHERE node.version IS NULL";
    my $sth = $dbh->prepare($sql);
    $sth->execute or croak $dbh->errstr;
    my @links;
    while ( my $link = $sth->fetchrow_array ) {
        push @links, $link;
    }
    return @links;
}

=item B<write_node_post_locking>

  $store->write_node_post_locking( node     => $node,
                                   content  => $content,
                                   links_to => \@links_to,
                                   metadata => \%metadata,
                                   plugins  => \@plugins   )
      or handle_error();

Writes the specified content into the specified node, then calls
C<post_write> on all supplied plugins, with arguments C<node>,
C<version>, C<content>, C<metadata>.

Making sure that locking/unlocking/transactions happen is left up to
you (or your chosen subclass). This method shouldn't really be used
directly as it might overwrite someone else's changes. Croaks on error
but otherwise returns true.

Supplying a ref to an array of nodes that this ones links to is
optional, but if you do supply it then this node will be returned when
calling C<list_backlinks> on the nodes in C<@links_to>. B<Note> that
if you don't supply the ref then the store will assume that this node
doesn't link to any others, and update itself accordingly.

The metadata hashref is also optional.

B<Note> on the metadata hashref: Any data in here that you wish to
access directly later must be a key-value pair in which the value is
either a scalar or a reference to an array of scalars.  For example:

  $wiki->write_node( "Calthorpe Arms", "nice pub", $checksum,
                     { category => [ "Pubs", "Bloomsbury" ],
                       postcode => "WC1X 8JR" } );

  # and later

  my @nodes = $wiki->list_nodes_by_metadata(
      metadata_type  => "category",
      metadata_value => "Pubs"             );

For more advanced usage (passing data through to registered plugins)
you may if you wish pass key-value pairs in which the value is a
hashref or an array of hashrefs. The data in the hashrefs will not be
stored as metadata; it will be checksummed and the checksum will be
stored instead (as C<__metadatatypename__checksum>). Such data can
I<only> be accessed via plugins.

=cut

sub write_node_post_locking {
    my ($self, %args) = @_;
    my ($node, $content, $links_to_ref, $metadata_ref) =
                                @args{ qw( node content links_to metadata) };
    my $dbh = $self->dbh;

    my $timestamp = $self->_get_timestamp();
    my @links_to = @{ $links_to_ref || [] }; # default to empty array
    my $version;

    # Either inserting a new page or updating an old one.
    my $sql = "SELECT count(*) FROM node WHERE name=" . $dbh->quote($node);
    my $exists = @{ $dbh->selectcol_arrayref($sql) }[0] || 0;
    if ($exists) {
        $sql = "SELECT max(version) FROM content
                WHERE name=" . $dbh->quote($node);
        $version = @{ $dbh->selectcol_arrayref($sql) }[0] || 0;
        croak "Can't get version number" unless $version;
        $version++;
        $sql = "UPDATE node SET version=" . $dbh->quote($version)
	     . ", text=" . $dbh->quote($content)
	     . ", modified=" . $dbh->quote($timestamp)
	     . " WHERE name=" . $dbh->quote($node);
	$dbh->do($sql) or croak "Error updating database: " . DBI->errstr;
    } else {
        $version = 1;
        $sql = "INSERT INTO node (name, version, text, modified)
                VALUES ("
             . join(", ", map { $dbh->quote($_) }
		              ($node, $version, $content, $timestamp)
                   )
             . ")";
	$dbh->do($sql) or croak "Error updating database: " . DBI->errstr;
    }

    # In either case we need to add to the history.
    $sql = "INSERT INTO content (name, version, text, modified)
            VALUES ("
         . join(", ", map { $dbh->quote($_) }
		          ($node, $version, $content, $timestamp)
               )
         . ")";
    $dbh->do($sql) or croak "Error updating database: " . DBI->errstr;

    # And to the backlinks.
    $dbh->do("DELETE FROM internal_links WHERE link_from="
             . $dbh->quote($node) ) or croak $dbh->errstr;
    foreach my $links_to ( @links_to ) {
        $sql = "INSERT INTO internal_links (link_from, link_to) VALUES ("
             . join(", ", map { $dbh->quote($_) } ( $node, $links_to ) ) . ")";
        # Better to drop a backlink or two than to lose the whole update.
        # Shevek wants a case-sensitive wiki, Jerakeen wants a case-insensitive
        # one, MySQL compares case-sensitively on varchars unless you add
        # the binary keyword.  Case-sensitivity to be revisited.
        eval { $dbh->do($sql); };
        carp "Couldn't index backlink: " . $dbh->errstr if $@;
    }

    # And also store any metadata.  Note that any entries already in the
    # metadata table refer to old versions, so we don't need to delete them.
    my %metadata = %{ $metadata_ref || {} }; # default to no metadata
    foreach my $type ( keys %metadata ) {
        my $val = $metadata{$type};

        # We might have one or many values; make an array now to merge cases.
        my @values = (ref $val and ref $val eq 'ARRAY') ? @$val : ( $val );

        # Find out whether all values for this type are scalars.
        my $all_scalars = 1;
        foreach my $value (@values) {
            $all_scalars = 0 if ref $value;
	}

        # If all values for this type are scalars, strip out any duplicates
        # and store the data.
        if ( $all_scalars ) {
            my %unique = map { $_ => 1 } @values;
            @values = keys %unique;

            foreach my $value ( @values ) {
                my $sql = "INSERT INTO metadata "
                    . "(node, version, metadata_type, metadata_value) VALUES ("
                    . join(", ", map { $dbh->quote($_) }
                                 ( $node, $version, $type, $value )
                          )
                    . ")";
	        $dbh->do($sql) or croak $dbh->errstr;
	    }
	} else {
        # Otherwise grab a checksum and store that.
            my $type_to_store  = "__" . $type . "__checksum";
            my $value_to_store = $self->_checksum_hashes( @values );
            my $sql = "INSERT INTO metadata "
                    . "(node, version, metadata_type, metadata_value) VALUES ("
                    . join(", ", map { $dbh->quote($_) }
                           ( $node, $version, $type_to_store, $value_to_store )
                          )
                    . ")";
	    $dbh->do($sql) or croak $dbh->errstr;
	}
    }

    # Finally call post_write on any plugins.
    my @plugins = @{ $args{plugins} || [ ] };
    foreach my $plugin (@plugins) {
        if ( $plugin->can( "post_write" ) ) {
            $plugin->post_write( node     => $node,
				 version  => $version,
				 content  => $content,
				 metadata => $metadata_ref );
	}
    }

    return 1;
}

# Returns the timestamp of now, unless epoch is supplied.
sub _get_timestamp {
    my $self = shift;
    # I don't care about no steenkin' timezones (yet).
    my $time = shift || localtime; # Overloaded by Time::Piece.
    unless( ref $time ) {
	$time = localtime($time); # Make it into an object for strftime
    }
    return $time->strftime($timestamp_fmt); # global
}

=item B<delete_node>

  $store->delete_node($node);

Deletes the node (whether it exists or not), croaks on error. Again,
doesn't do any kind of locking. You probably don't want to let anyone
except Wiki admins call this. Removes all the node's history as well.

=cut

sub delete_node {
    my ($self, $node) = @_;
    my $dbh = $self->dbh;
    my $name = $dbh->quote($node);
    # Should start a transaction here.  FIXME.
    my $sql = "DELETE FROM node WHERE name=$name";
    $dbh->do($sql) or croak "Deletion failed: " . DBI->errstr;
    $sql = "DELETE FROM content WHERE name=$name";
    $dbh->do($sql) or croak "Deletion failed: " . DBI->errstr;
    $sql = "DELETE FROM internal_links WHERE link_from=$name";
    $dbh->do($sql) or croak $dbh->errstr;
    $sql = "DELETE FROM metadata WHERE node=$name";
    $dbh->do($sql) or croak $dbh->errstr;
    # And finish it here.
    return 1;
}

=item B<list_recent_changes>

  # Changes in last 7 days.
  my @nodes = $store->list_recent_changes( days => 7 );

  # Changes since a given time.
  my @nodes = $store->list_recent_changes( since => 1036235131 );

  # Most recent change and its details.
  my @nodes = $store->list_recent_changes( last_n_changes => 1 );
  print "Node:          $nodes[0]{name}";
  print "Last modified: $nodes[0]{last_modified}";
  print "Comment:       $nodes[0]{metadata}{comment}";

  # Last 5 restaurant nodes edited.
  my @nodes = $store->list_recent_changes(
      last_n_changes => 5,
      metadata_is    => { category => "Restaurants" }
  );

  # Last 5 nodes edited by Kake.
  my @nodes = $store->list_recent_changes(
      last_n_changes => 5,
      metadata_was   => { username => "Kake" }
  );

  # Last 10 changes that weren't minor edits.
  my @nodes = $store->list_recent_changes(
      last_n_changes => 5,
      metadata_wasnt  => { edit_type => "Minor tidying" }
  );

You I<must> supply one of the following constraints: C<days>
(integer), C<since> (epoch), C<last_n_changes> (integer). You I<may>
also supply one of the following constraints: C<metadata_is>,
C<metadata_isnt>, C<metadata_was>, C<metadata_wasnt>. Each should be a
ref to a hash with a single key and value.

C<metadata_is> and C<metadata_isnt> look only at the metadata that the
node I<currently> has. C<metadata_was> and C<metadata_wasnt> take into
account the metadata of previous versions of a node. B<NOTE:> Only one
of these constraints will be honoured, so please only supply one. This
may change in the future. (For avoidance of confusion - they are
examined in the following order: is, isnt, was, wasnt.)

Returns results as an array, in reverse chronological order.  Each
element of the array is a reference to a hash with the following entries:

=over 4

=item * B<name>: the name of the node

=item * B<version>: the latest version number

=item * B<last_modified>: the timestamp of when it was last modified

=item * B<metadata>: a ref to a hash containing any metadata attached
to the current version of the node

=back

Unless you supply C<metadata_was> or C<metadata_wasnt>, each node will
only be returned once, regardless of how many times it has been
changed recently.

B<Future plans and thoughts for list_recent_changes>

This method will croak if you try to put more than one key/value in
the metadata constraint hashes, because the API for that is not yet
decided. It'll be nice in the future to be able to do for example:

  # All minor edits made by Earle in the last week.
  my @nodes = $store->list_recent_changes(
      days           => 7,
      metadata_was   => { username  => "Earle",
                          edit_type => "Minor tidying." }
  );

  # The last three Holborn pubs whose entries were edited.
  my @nodes = $store->list_recent_changes(
      last_n_changes => 3,
      metadata_is    => { category => [ "Pubs", "Holborn" ] }
  );

The question is a nice syntax for specifying how the criteria should
be ANDed or ORed. This might make sense done as a plugin.

=cut

sub list_recent_changes {
    my $self = shift;
    my %args = @_;
    if ($args{since}) {
        return $self->_find_recent_changes_by_criteria( %args );
    } elsif ( $args{days} ) {
        my $now = localtime;
	my $then = $now - ( ONE_DAY * $args{days} );
        $args{since} = $then;
        delete $args{days};
        return $self->_find_recent_changes_by_criteria( %args );
    } elsif ( $args{last_n_changes} ) {
        $args{limit} = delete $args{last_n_changes};
        return $self->_find_recent_changes_by_criteria( %args );
    } else {
	croak "Need to supply a parameter";
    }
}

sub _find_recent_changes_by_criteria {
    my ($self, %args) = @_;
    my ($since, $limit, $metadata_is,  $metadata_isnt,
                        $metadata_was, $metadata_wasnt ) =
                             @args{ qw( since limit metadata_is metadata_isnt
                                                metadata_was metadata_wasnt) };
    my $dbh = $self->dbh;

    my @where;
    my $main_table = "node";
    if ( $metadata_is ) {
        if ( scalar keys %$metadata_is > 1 ) {
            croak "metadata_is must have one key and one value only";
        }
        my ($type) = keys %$metadata_is;
        my $value  = $metadata_is->{$type};
        croak "metadata_is must have one key and one value only"
          if ref $value;
	push @where, "metadata.metadata_type=" . $dbh->quote($type);
	push @where, "metadata.metadata_value=" . $dbh->quote($value);
    } elsif ( $metadata_isnt ) {
        if ( scalar keys %$metadata_isnt > 1 ) {
            croak "metadata_isnt must have one key and one value only";
	}
        my ($type) = keys %$metadata_isnt;
	my $value  = $metadata_isnt->{$type};
        croak "metadata_isnt must have one key and one value only"
          if ref $value;
        my @omit = $self->list_nodes_by_metadata(
            metadata_type  => $type,
            metadata_value => $value );
        push @where, "node.name NOT IN ("
                   . join(",", map { $dbh->quote($_) } @omit ) . ")"
          if scalar @omit;
    } elsif ( $metadata_was ) {
        $main_table = "content";
        if ( scalar keys %$metadata_was > 1 ) {
            croak "metadata_was must have one key and one value only";
	}
        my ($type) = keys %$metadata_was;
	my $value  = $metadata_was->{$type};
            croak "metadata_was must have one key and one value only"
          if ref $value;
        push @where, "metadata.metadata_type=" . $dbh->quote($type);
	push @where, "metadata.metadata_value=" . $dbh->quote($value);
    } elsif ( $metadata_wasnt ) {
        $main_table = "content";
        if ( scalar keys %$metadata_wasnt > 1 ) {
            croak "metadata_wasnt must have one key and one value only";
	}
        my ($type) = keys %$metadata_wasnt;
	my $value  = $metadata_wasnt->{$type};
        croak "metadata_wasnt must have one key and one value only"
         if ref $value;
        my @omits = $self->_find_recent_changes_by_criteria(
            since        => $since,
            metadata_was => $metadata_wasnt,
        );
        foreach my $omit ( @omits ) {
            push @where, "( content.name != " . $dbh->quote($omit->{name})
                 . "  OR content.version != " . $dbh->quote($omit->{version})
                 . ")";
	}
    }

    if ( $since ) {
        my $timestamp = $self->_get_timestamp( $since );
        push @where, "$main_table.modified >= " . $dbh->quote($timestamp);
    }

    my $sql = "SELECT DISTINCT
                               $main_table.name,
                               $main_table.version,
                               $main_table.modified
               FROM $main_table
                    LEFT JOIN metadata
                           ON $main_table.name=metadata.node
                          AND $main_table.version=metadata.version
              "
            . ( scalar @where ? " WHERE " . join(" AND ",@where)
			                     : "" )
            . " ORDER BY $main_table.modified DESC";
    if ( $limit ) {
        croak "Bad argument $limit" unless $limit =~ /^\d+$/;
        $sql .= " LIMIT $limit";
    }

    my $nodesref = $dbh->selectall_arrayref($sql);
    my @finds = map { { name          => $_->[0],
			version       => $_->[1],
			last_modified => $_->[2] }
		    } @$nodesref;
    foreach my $find ( @finds ) {
        my %metadata;
        my $sth = $dbh->prepare( "SELECT metadata_type, metadata_value
                                  FROM metadata WHERE node=? AND version=?" );
        $sth->execute( $find->{name}, $find->{version} );
        while ( my ($type, $value) = $sth->fetchrow_array ) {
	    if ( defined $metadata{$type} ) {
                push @{$metadata{$type}}, $value;
	    } else {
                $metadata{$type} = [ $value ];
            }
	}
        $find->{metadata} = \%metadata;
    }
    return @finds;
}

=item B<list_all_nodes>

  my @nodes = $store->list_all_nodes();

Returns a list containing the name of every existing node.  The list
won't be in any kind of order; do any sorting in your calling script.

=cut

sub list_all_nodes {
    my $self = shift;
    my $dbh = $self->dbh;
    my $sql = "SELECT name FROM node;";
    my $nodes = $dbh->selectall_arrayref($sql); 
    return ( map { $_->[0] } (@$nodes) );
}

=item B<list_nodes_by_metadata>

  # All documentation nodes.
  my @nodes = $store->list_nodes_by_metadata(
      metadata_type  => "category",
      metadata_value => "documentation",
      ignore_case    => 1,   # optional but recommended (see below)
  );

  # All pubs in Hammersmith.
  my @pubs = $store->list_nodes_by_metadata(
      metadata_type  => "category",
      metadata_value => "Pub",
  );
  my @hsm  = $store->list_nodes_by_metadata(
      metadata_type  => "category",
      metadata_value  => "Hammersmith",
  );
  my @results = my_l33t_method_for_ANDing_arrays( \@pubs, \@hsm );

Returns a list containing the name of every node whose caller-supplied
metadata matches the criteria given in the parameters.

By default, the case-sensitivity of both C<metadata_type> and
C<metadata_value> depends on your database - if it will return rows
with an attribute value of "Pubs" when you asked for "pubs", or not.
If you supply a true value to the C<ignore_case> parameter, then you
can be sure of its being case-insensitive.  This is recommended.

If you don't supply any criteria then you'll get an empty list.

This is a really really really simple way of finding things; if you
want to be more complicated then you'll need to call the method
multiple times and combine the results yourself, or write a plugin.

=cut

sub list_nodes_by_metadata {
    my ($self, %args) = @_;
    my ( $type, $value ) = @args{ qw( metadata_type metadata_value ) };
    return () unless $type;

    my $dbh = $self->dbh;
    if ( $args{ignore_case} ) {
        $type  = lc( $type  );
        $value = lc( $value );
    }
    my $sql =
         $self->_get_list_by_metadata_sql( ignore_case => $args{ignore_case} );
    my $sth = $dbh->prepare( $sql );
    $sth->execute( $type, $value );
    my @nodes;
    while ( my ($node) = $sth->fetchrow_array ) {
        push @nodes, $node;
    }
    return @nodes;
}

sub _get_list_by_metadata_sql {
    # can be over-ridden by database-specific subclasses
    return "SELECT node.name FROM node, metadata"
         . " WHERE node.name=metadata.node"
         . " AND node.version=metadata.version"
         . " AND metadata.metadata_type = ? "
         . " AND metadata.metadata_value = ? ";
}

=item B<dbh>

  my $dbh = $store->dbh;

Returns the database handle belonging to this storage backend instance.

=cut

sub dbh {
    my $self = shift;
    return $self->{_dbh};
}

=item B<dbname>

  my $dbname = $store->dbname;

Returns the name of the database used for backend storage.

=cut

sub dbname {
    my $self = shift;
    return $self->{_dbname};
}

=item B<dbuser>

  my $dbuser = $store->dbuser;

Returns the username used to connect to the database used for backend storage.

=cut

sub dbuser {
    my $self = shift;
    return $self->{_dbuser};
}

=item B<dbpass>

  my $dbpass = $store->dbpass;

Returns the password used to connect to the database used for backend storage.

=cut

sub dbpass {
    my $self = shift;
    return $self->{_dbpass};
}

=item B<dbhost>

  my $dbhost = $store->dbhost;

Returns the optional host used to connect to the database used for
backend storage.

=cut

sub dbhost {
    my $self = shift;
    return $self->{_dbhost};
}

# Cleanup.
sub DESTROY {
    my $self = shift;
    my $dbh = $self->dbh;
    $dbh->disconnect if $dbh;
}

1;