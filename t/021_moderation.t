use strict;
use CGI::Wiki::TestLib;
use Test::More;
use Time::Piece;

if ( scalar @CGI::Wiki::TestLib::wiki_info == 0 ) {
    plan skip_all => "no backends configured";
} else {
    plan tests => ( 39 * scalar @CGI::Wiki::TestLib::wiki_info );
}

my $iterator = CGI::Wiki::TestLib->new_wiki_maker;

while ( my $wiki = $iterator->new_wiki ) {
    # Put some test data in.
    $wiki->write_node( "Home", "This is the home node." )
      or die "Couldn't write node";

	# Now add another version
    my %node_data = $wiki->retrieve_node("Home");

    ok( $wiki->write_node("Home", "xx", $node_data{checksum}),
        "write_node succeeds when node matches checksum" );

	# Fetch it with and without specifying a version
    my %new_node_data = $wiki->retrieve_node("Home");
    my %new_node_data_v = $wiki->retrieve_node(name=>"Home", version=>$new_node_data{version});
    print "# version now: [$new_node_data{version}]\n";
    is( $new_node_data{version}, $node_data{version} + 1,
        "...and the version number is updated on successful writing" );
    is( $new_node_data{version}, $new_node_data_v{version},
        "...and the version number is updated on successful writing" );

	# Ensure that the moderation required flag isn't set on the node
	is( $node_data{node_requires_moderation}, '0', "New node correctly doesn't require moderation" );
	is( $new_node_data{node_requires_moderation}, '0', "Nor does it require moderation after being updated" );
	is( $new_node_data_v{node_requires_moderation}, '0', "Nor does it require moderation after being updated via version" );


	# Ensure the moderated flag is set on the two entries in content
	is( $node_data{moderated}, '1', "No moderation required, so is moderated" );
	is( $new_node_data{moderated}, '1', "No moderation required, so is moderated" );
	is( $new_node_data_v{moderated}, '1', "No moderation required, so is moderated" );


	# Now add a new node requiring moderation
    $wiki->write_node( "Moderation", "This is the moderated node.", undef, undef, 1);
    my %mn_data = $wiki->retrieve_node("Moderation");
	is( $mn_data{moderated}, '0', "First version shouldn't be moderated" );
	is( $mn_data{node_requires_moderation}, '1', "New node needs moderation" );

	# Shouldn't have the text if fetched without the version
	is( $mn_data{content}, "=== This page has yet to moderated. ===", "First version isn't moderated" );

	# If we fetch with a version, we should get the text
    my %mnv_data = $wiki->retrieve_node(name=>"Moderation", version=>1);
	is( $mnv_data{content}, "This is the moderated node.", "Should get text if a version is given" );

	is( $mnv_data{moderated}, '0', "First version shouldn't be moderated" );
	is( $mnv_data{node_requires_moderation}, '1', "New node needs moderation" );


	# Update it
    ok( $wiki->write_node("Moderation", "yy", $mn_data{checksum}),
		"Can update where moderation is enabled" );
    my %nmn_data = $wiki->retrieve_node("Moderation");
    my %nmnv_data = $wiki->retrieve_node(name=>"Moderation", version=>2);

	# Check content was updated right
	is( $nmnv_data{content}, "yy", "Version 2 text");

	# Should still be the same as before (unmoderated v1)
	is_deeply(\%mn_data,\%nmn_data, "Should still be the unmod first ver");
	is( $nmn_data{content}, "=== This page has yet to moderated. ===", "No version is moderated" );

	# Check node requires it still
	is( $nmnv_data{node_requires_moderation}, '1', "New node needs moderation" );

	# Check content not moderated
	is( $nmnv_data{moderated}, '0', "Second version shouldn't be moderated" );


	# Add the third entry
    ok( $wiki->write_node("Moderation", "foo foo", $nmn_data{checksum}),
		"Can update where moderation is enabled" );
    my %mn3_data = $wiki->retrieve_node("Moderation");
	is( $mn3_data{node_requires_moderation}, '1', "New node needs moderation" );
	is( $mn3_data{moderated}, '0', "Third version shouldn't be moderated" );
	is( $mn3_data{content}, "=== This page has yet to moderated. ===", "No version is moderated" );


	# Moderate the second entry
	ok( $wiki->moderate_node("Moderation", 2), "Can't moderate 2nd version" );
	%node_data = $wiki->retrieve_node(name=>"Moderation");
	my %mmn2 = $wiki->retrieve_node(name=>"Moderation",version=>2);

	# Node should now hold 2nd version 
	is( $mmn2{moderated}, '1', "Second version should now be moderated" );
	is( $mmn2{node_requires_moderation}, '1', "Still requires moderation" );
	is( $node_data{moderated}, '1', "Current version should now be moderated" );
	is( $node_data{node_requires_moderation}, '1', "Still requires moderation" );
	is( $node_data{content}, "yy", "Node should be second version" );
	is( $node_data{version}, "2", "Node should be second version" );


	# Moderate the first entry
	ok( $wiki->moderate_node(name=>"Moderation", version=>1), "Can't moderate 1st version" );
	%node_data = $wiki->retrieve_node(name=>"Moderation");
	my %mmn1 = $wiki->retrieve_node(name=>"Moderation",version=>1);

	# First entry should now be moderated, but node shouldn't be changed
	is( $mmn1{moderated}, '1', "First version should now be moderated" );
	is( $mmn1{node_requires_moderation}, '1', "Still requires moderation" );
	is( $node_data{moderated}, '1', "Current version should still be moderated" );
	is( $node_data{node_requires_moderation}, '1', "Still requires moderation" );
	is( $node_data{content}, "yy", "Node should still be second version" );
	is( $node_data{version}, "2", "Node should still be second version" );


	# Moderate the third entry
#	ok( $wiki->moderate_node(name=>"Moderation", version=>3), "Can't moderate 3rd version" );


	# Add a 4th entry
}
