package CGI::Wiki::Search::DBIxFTS;

use strict;
use DBIx::FullTextSearch;
use Carp "croak";

use vars qw( @ISA $VERSION );

$VERSION = 0.04;

=head1 NAME

CGI::Wiki::Search::DBIxFTS - DBIx::FullTextSearch search plugin for CGI::Wiki

=head1 REQUIRES

DBIx::FullTextSearch

=head1 SYNOPSIS

  my $store = CGI::Wiki::Store::MySQL->new(
                                    dbname => "wiki", dbpass=>"wiki" );
  my $search = CGI::Wiki::Search::DBIxFTS->new( dbh => $store->dbh );
  my %wombat_nodes = $search->search_nodes("wombat");

Provides search-related methods for CGI::Wiki

=cut

=head1 METHODS

=over 4

=item B<new>

  my $search = CGI::Wiki::Search::DBIxFTS->new( dbh => $dbh );

You must supply a handle to a database that has the
DBIx::FullTextSearch indexes already set up. (Currently though there's
no checking that what you supply is even a database handle at all, let
alone one that is compatible with DBIx::FullTextSearch.)

=cut

sub new {
    my ($class, @args) = @_;
    my $self = {};
    bless $self, $class;
    return $self->_init(@args);
}

sub _init {
    my ($self, %args) = @_;
    croak "Must supply a database handle" unless $args{dbh};
    $self->{_dbh} = $args{dbh};
    return $self;
}

=item B<search_nodes>

  # Find all the nodes which contain both the word 'expert' and the
  # phrase 'wombat defenestration'.
  %results = $search->search_nodes('expert "wombat defenestration"');

  # Find all the nodes which contain at least one of the words
  # 'buffy', 'pony', and 'pie'.
  %results = $search->search_nodes('buffy pony pie', 'OR');

Returns a (possibly empty) hash whose keys are the node names and
whose values are the scores in some kind of relevance-scoring system I
haven't entirely come up with yet. For OR searches, this could
initially be the number of terms that appear in the node, perhaps.

Defaults to AND searches (if $and_or is not supplied, or is anything
other than C<OR> or C<or>).

Searches are case-insensitive.

=cut

sub search_nodes {
    my ($self, $termstr, $and_or) = @_;

    $and_or = uc($and_or);
    unless ( defined $and_or and $and_or eq "OR" ) {
        $and_or = "AND";
    }

    # Note: Not sure yet whether the term extraction below is going to be
    # common between backends.  Move it back into CGI::Wiki if it turns
    # out to be.

    # Extract individual search terms - first phrases (between double quotes).
    my @terms = ($termstr =~ m/"([^"]+)"/g);
    $termstr =~ s/"[^"]*"//g;
    # And now the phrases are gone, just split on whitespace.
    push @terms, split(/\s+/, $termstr);

    # If this is an AND search, tell DBIx::FTS we want every term.
    @terms = map { "+$_" } @terms if $and_or eq "AND";

    # Open and perform the FTS.
    my $dbh = $self->{_dbh};
    my $fts = DBIx::FullTextSearch->open($dbh, "_content_and_title_fts");
    my @finds = $fts->econtains(@terms);

    # Well, no scoring yet, you see.
    return map { $_ => 1 } @finds;
}

=item B<index_node>

  $search->index_node($node);

Indexes or reindexes the given node in the FTS indexes in the backend
storage.

=cut

sub index_node {
    my ($self, $node) = @_;

    my $dbh = $self->{_dbh};
    my $fts_all = DBIx::FullTextSearch->open($dbh, "_content_and_title_fts");
    my $fts_titles = DBIx::FullTextSearch->open($dbh, "_title_fts");

    $fts_all->index_document($node);
    $fts_titles->index_document($node);

    delete $fts_all->{db_backend}; # hack around buglet in DBIx::FTS
    delete $fts_titles->{db_backend}; # ditto
}

=item B<delete_node>

  $search->delete_node($node);

Removes the given node from the search indexes.  NOTE: It's up to you to
make sure the node is removed from the backend store.  Croaks on error,
returns true on success.

=cut

sub delete_node {
    my ($self, $node) = @_;
    my $dbh = $self->{_dbh};
    my $fts_all    = DBIx::FullTextSearch->open($dbh, "_content_and_title_fts")
        or croak "Can't open _content_and_title_fts";
    my $fts_titles = DBIx::FullTextSearch->open($dbh, "_title_fts")
        or croak "Can't open _title_fts";
    eval { $fts_all->delete_document($node); };
    croak "Couldn't delete from full index: $@" if $@;
    eval { $fts_titles->delete_document($node); };
    croak "Couldn't delete from title-only index: $@" if $@;
    return 1;
}

=item B<supports_phrase_searches>

  if ( $search->supports_phrase_searches ) {
      return $search->search_nodes( '"fox in socks"' );
  }

Returns true if this search backend supports phrase searching, and
false otherwise.

=cut

sub supports_phrase_searches {
    return 1;
}

=back

=head1 SEE ALSO

L<CGI::Wiki>

=cut

1;
