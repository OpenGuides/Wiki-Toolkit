package Wiki::Toolkit::Store::SQLite;

use strict;

use vars qw( @ISA $VERSION );

use Wiki::Toolkit::Store::Database;
use Carp qw/carp croak/;

@ISA = qw( Wiki::Toolkit::Store::Database );
$VERSION = 0.05;

=head1 NAME

Wiki::Toolkit::Store::SQLite - SQLite storage backend for Wiki::Toolkit

=head1 SYNOPSIS

See Wiki::Toolkit::Store::Database

=cut

# Internal method to return the data source string required by DBI.
sub _dsn {
    my ($self, $dbname) = @_;
    return "dbi:SQLite:dbname=$dbname";
}

=head1 METHODS

=over 4

=item B<new>

  my $store = Wiki::Toolkit::Store::SQLite->new( dbname => "wiki" );

The dbname parameter is mandatory.

=cut

sub new {
    my ($class, %args) = @_;
    my $self = {};
    bless $self, $class;
    @args{qw(dbuser dbpass)} = ("", "");  # for the parent class _init
    return $self->_init(%args);
}

=over 4

=item B<check_and_write_node>

  $store->check_and_write_node( node     => $node,
				checksum => $checksum,
                                %other_args );

Locks the node, verifies the checksum, calls
C<write_node_post_locking> with all supplied arguments, unlocks the
node. Returns 1 on successful writing, 0 if checksum doesn't match,
croaks on error.

=cut

sub check_and_write_node {
    my ($self, %args) = @_;
    my ($node, $checksum) = @args{qw( node checksum )};

    my $dbh = $self->{_dbh};
    $dbh->{AutoCommit} = 0;

    my $ok = eval {
        $dbh->do("END TRANSACTION");
        $dbh->do("BEGIN TRANSACTION");
        $self->verify_checksum($node, $checksum) or return 0;
        $self->write_node_post_locking( %args );
    };
    if ($@) {
        my $error = $@;
        $dbh->rollback;
	$dbh->{AutoCommit} = 1;
	if (   $error =~ /database is locked/
            or $error =~ /DBI connect.+failed/ ) {
            return 0;
        } else {
            croak "Unhandled error: [$error]";
        }
    } else {
        $dbh->commit;
	$dbh->{AutoCommit} = 1;
	return $ok;
    }
}

sub _get_list_by_metadata_sql {
    my ($self, %args) = @_;
    if ( $args{ignore_case} ) {
        return "SELECT node.name FROM node, metadata"
             . " WHERE node.id=metadata.node_id"
             . " AND node.version=metadata.version"
             . " AND metadata.metadata_type LIKE ? "
             . " AND metadata.metadata_value LIKE ? ";
    } else {
        return "SELECT node.name FROM node, metadata"
             . " WHERE node.id=metadata.node_id"
             . " AND node.version=metadata.version"
             . " AND metadata.metadata_type = ? "
             . " AND metadata.metadata_value = ? ";
    }
}

sub _get_list_by_missing_metadata_sql {
    my ($self, %args) = @_;

	my $sql = "";
    if ( $args{ignore_case} ) {
        $sql = "SELECT node.name FROM node, metadata"
             . " WHERE node.id=metadata.node_id"
             . " AND node.version=metadata.version"
             . " AND metadata.metadata_type LIKE ? ";
    } else {
        $sql = "SELECT node.name FROM node, metadata"
             . " WHERE node.id=metadata.node_id"
             . " AND node.version=metadata.version"
             . " AND metadata.metadata_type = ? ";
    }

	if( $args{with_value} ) {
		if ( $args{ignore_case} ) {
             $sql .= " AND NOT metadata.metadata_value LIKE ? ";
		} else {
             $sql .= " AND NOT metadata.metadata_value = ? ";
		}
	} else {
		$sql .= "AND (metadata.metadata_value IS NULL OR LENGHT(metadata.metadata_value) == 0) ";
	}
	return $sql;
}

sub _get_comparison_sql {
    my ($self, %args) = @_;
    if ( $args{ignore_case} ) {
        return "$args{thing1} LIKE $args{thing2}";
    } else {
        return "$args{thing1} = $args{thing2}";
    }
}

sub _get_node_exists_ignore_case_sql {
    return "SELECT name FROM node WHERE name LIKE ? ";
}

1;
