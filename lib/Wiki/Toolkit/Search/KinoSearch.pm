package Wiki::Toolkit::Search::KinoSearch;
use strict;
our $VERSION = '0.01';

use base 'Wiki::Toolkit::Search::Base';

#use File::Spec::Functions qw(catfile);
use File::Spec;
use KinoSearch::InvIndexer;
use KinoSearch::Analysis::PolyAnalyzer;

=head1 NAME

Wiki::Toolkit::Search::KinoSearch - Use KinoSearch to search your Wiki::Toolkit wiki.

=head1 SYNOPSIS

  my $search = Wiki::Toolkit::Search::KinoSearch->new( path => "/var/KinoSearch/wiki" );
  my %wombat_nodes = $search->search_nodes("wombat");

Provides search-related methods for L<Wiki::Toolkit>.

=cut

=head1 METHODS

=over 4

=item B<new>

  my $search = Wiki::Toolkit::Search::KinoSearch->new( path => "/var/KinoSearch/wiki" );

Takes only one parameter, which is mandatory. C<path> must be a directory
for storing the indexed data.  It should exist and be writeable.

=cut

sub _init {
    my ( $self, %args ) = @_;
    $self->{_dir} = $args{path};
    return $self;
}

sub _dir { shift->{_dir} }

sub _analyzer {
    KinoSearch::Analysis::PolyAnalyzer->new( language => 'en', );
}

sub _indexer {
    my ($self) = @_;
    my $indexer = KinoSearch::InvIndexer->new(
        analyzer => $self->_analyzer,
        invindex => $self->_dir,
        create   => 1,
    );
    $indexer->spec_field( name => 'title' );
    $indexer->spec_field(
        name       => 'body_text',
        vectorized => 1,
    );
    return $indexer;
}

sub index_node {
    my ( $self, $node, $content ) = @_;
    my $indexer = $self->_indexer;
    my $doc     = $indexer->new_doc;
    $doc->set_value( title     => $node );
    $doc->set_value( body_text => $content );
    $indexer->add_doc($doc);
    $indexer->finish( optimize => $self->optimize );
}

sub _searcher {
    my ($self) = @_;
    KinoSearch::Searcher->new(
        invindex => $self->_dir,
        analyzer => $self->_analyzer,
    );
}

sub _search_nodes {
    my ( $self, $query ) = @_;
    $self->_searcher->search($query);
}

sub search_nodes {
    my ( $self, @args ) = @_;
    my $hits    = $self->_search_nodes(@args);
    my $results = {};
    while ( $hit = $hits->fetch_hit_hashref ) {
        $results->{ $hit->{title} } = $hit->{score};
    }
    return %$results;
}

# sub _fuzzy_match {
#     my ( $self, $string, $canonical ) = @_;
#     return
#       map { $_ => ( $_ eq $string ? 2 : 1 ) }
#       $self->_search_nodes("fuzzy:$canonical");
# }

# sub indexed {
#     my ( $self, $id ) = @_;
#     my $term = Plucene::Index::Term->new( { field => 'id', text => $id } );
#     return $self->_reader->doc_freq($term);
# }

sub optimize { 1 }

sub delete_node {
    my ( $self, $id ) = @_;
    my $term = KinoSearch::Index::Term->new( title => $id );
    my $indexer = $self->_indexer;
    $indexer->delete_docs_by_term($term);
    $indexer->finish( optimize => $self->optimize );
}

sub supports_phrase_searches { return 0; }
sub supports_fuzzy_searches  { return 0; }

1;
__END__

=back

=head1 TODO

=over 4

=item Phrase Searching 
=item Fuzzy Matching

=head1 SEE ALSO

L<Wiki::Toolkit>, L<Wiki::Toolkit::Search::Base>.

=cut

