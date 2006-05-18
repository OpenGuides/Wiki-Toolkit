use strict;
use Wiki::Toolkit::TestLib;
use Test::More;

if ( scalar @Wiki::Toolkit::TestLib::wiki_info == 0 ) {
    plan skip_all => "no backends configured";
} else {
    plan tests => ( 9 * scalar @Wiki::Toolkit::TestLib::wiki_info );
}

my $iterator = Wiki::Toolkit::TestLib->new_wiki_maker;

while ( my $wiki = $iterator->new_wiki ) {
	# Add three base nodes
    foreach my $name ( qw( Carrots Handbags Cheese ) ) {
        $wiki->write_node( $name, "content" ) or die "Can't write node";
    }

	# Add three more versions of Cheese
	my %node = $wiki->retrieve_node("Cheese");
	$wiki->write_node("Cheese", "Content v2", $node{checksum}, { "foo" => "bar" } ) or die "Can't write node";

	%node = $wiki->retrieve_node("Cheese");
	$wiki->write_node("Cheese", "Content v3", $node{checksum}, { "foo" => "bar", "bar" => "foo" } ) or die "Can't write node";

	%node = $wiki->retrieve_node("Cheese");
	$wiki->write_node("Cheese", "Content v4", $node{checksum} ) or die "Can't write node";


	# Fetch all the versions
	my @all_versions = $wiki->list_node_all_versions("Cheese");

	is( scalar @all_versions, 4, "list_node_all_versions gives the right number back" );

	# Check them
	is( $all_versions[0]->{'version'}, 4, "right ordering" );
	is( $all_versions[1]->{'version'}, 3, "right ordering" );
	is( $all_versions[2]->{'version'}, 2, "right ordering" );
	is( $all_versions[3]->{'version'}, 1, "right ordering" );
	is( $all_versions[0]->{'name'}, "Cheese", "right node" );
	is( $all_versions[1]->{'name'}, "Cheese", "right node" );
	is( $all_versions[2]->{'name'}, "Cheese", "right node" );
	is( $all_versions[3]->{'name'}, "Cheese", "right node" );


	# Fetch with content too

	# With metadata

	# With both
    #is_deeply( [sort @all_nodes], [ qw( Carrots Cheese Handbags ) ],
    #           "...and the right ones, too" );
}

