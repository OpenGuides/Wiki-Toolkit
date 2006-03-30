use strict;
use CGI::Wiki::TestLib;
use Test::More;
use Time::Piece;

if ( scalar @CGI::Wiki::TestLib::wiki_info == 0 ) {
    plan skip_all => "no backends configured";
} else {
    plan tests => ( 13 * scalar @CGI::Wiki::TestLib::wiki_info );
}

my $iterator = CGI::Wiki::TestLib->new_wiki_maker;

while ( my $wiki = $iterator->new_wiki ) {
	my %non_existant_node = (content=>"", version=>0, last_modified=>"", checksum=>"d41d8cd98f00b204e9800998ecf8427e", moderated=>undef, node_requires_moderation=>undef, metadata=>{});


	# Ensure our formatter supports renaming
	ok( $wiki->{_formatter}->can("rename_links"), "The formatter must be able to rename links for these tests to work" );


	# Add three pages, which all link to each other, where there
	#  are multiple versions of two of the three

	$wiki->write_node( "NodeOne", "This is the first node, which links to NodeTwo, NodeThree, [NodeTwo] and [NodeThree | Node Three]." )
		or die "Couldn't write node";
    my %nodeone1 = $wiki->retrieve_node("NodeOne");
	$wiki->write_node( "NodeOne", "This is the second version of the first node, which links to NodeTwo, NodeThree, [NodeTwo], [NodeFour|Node Four] and [NodeThree | Node Three].", $nodeone1{checksum} )
		or die "Couldn't write node";
    my %nodeone2 = $wiki->retrieve_node("NodeOne");

	$wiki->write_node( "NodeTwo", "This is the second node, which links to just NodeOne [NodeOne | twice].")
		or die "Couldn't write node";
    my %nodetwo1 = $wiki->retrieve_node("NodeTwo");
	$wiki->write_node( "NodeTwo", "This is the second version of the second node, which links to [NodeTwo|itself] and NodeOne", $nodetwo1{checksum})
		or die "Couldn't write node";
    my %nodetwo2 = $wiki->retrieve_node("NodeTwo");

	$wiki->write_node( "NodeThree", "This is the third node, which links to all 3 via NodeOne, NodeTwo and [NodeThree]")
		or die "Couldn't write node";
    my %nodethree1 = $wiki->retrieve_node("NodeThree");


	# Rename NodeOne to NodeFoo, without new versions
	# (Don't pass in the key names)
	ok( $wiki->rename_node("NodeOne", "NodeFoo"), "Rename node");

	# Should be able to find it as NodeFoo, but not NodeOne
	my %asnode1 = $wiki->retrieve_node("NodeOne");
	my %asnodef = $wiki->retrieve_node("NodeFoo");

	is_deeply( \%asnode1, \%non_existant_node, "Renamed to NodeFoo" );
	is_deeply( \%asnodef, \%nodeone2, "Renamed to NodeFoo" );
	is( "This is the second version of the first node, which links to NodeTwo, NodeThree, [NodeTwo], [NodeFour|Node Four] and [NodeThree | Node Three].", $asnodef{"content"}, "no change needed to node" );

	# Check that the other pages were updated as required
	# NodeTwo linked implicitly
	my %anode2 = $wiki->retrieve_node("NodeTwo");
	is( "This is the second version of the second node, which links to [NodeTwo|itself] and NodeFoo", $anode2{'content'}, "implicit link was updated" );
	# NodeThree linked implicitly
	my %anode3 = $wiki->retrieve_node("NodeThree");
	is( "This is the third node, which links to all 3 via NodeFoo, NodeTwo and [NodeThree]", $anode3{'content'}, "implicit link was updated" );



	# Rename it back to NodeOne
	# (Pass in the key names)
	ok( $wiki->rename_node(new_name=>"NodeOne", old_name=>"NodeFoo"), "Rename node");

	# Should be able to find it as NodeOne again, but not NodeFoo
	%asnode1 = $wiki->retrieve_node("NodeOne");
	%asnodef = $wiki->retrieve_node("NodeFoo");

	is_deeply( \%asnodef, \%non_existant_node, "Renamed to NodeOne" );
	is_deeply( \%asnode1, \%nodeone2, "Renamed to NodeFoo" );
	is( "This is the second version of the first node, which links to NodeTwo, NodeThree, [NodeTwo], [NodeFour|Node Four] and [NodeThree | Node Three].", $asnode1{"content"}, "no change needed to node" );

	# Now check two and three changed back
	%anode2 = $wiki->retrieve_node("NodeTwo");
	is( "This is the second version of the second node, which links to [NodeTwo|itself] and NodeOne", $anode2{'content'}, "implicit link was updated" );
	%anode3 = $wiki->retrieve_node("NodeThree");
	is( "This is the third node, which links to all 3 via NodeOne, NodeTwo and [NodeThree]", $anode3{'content'}, "implicit link was updated" );


	# Tweak the formatter - swap to extended links from implicit

	# Rename NodeTwo to NodeFooBar


	# Now have the new version stuff active
}
