use strict;
use CGI::Wiki::TestLib;
use Test::More tests => ( 4 * scalar @CGI::Wiki::TestLib::wiki_info );

my $iterator = CGI::Wiki::TestLib->new_wiki_maker;

while ( my $wiki = $iterator->new_wiki ) {
    $wiki->write_node("A Node", "Node content.") or die "Can't write node";

    # Test deletion of an existing node.
    eval { $wiki->delete_node("A Node") };
    is( $@, "", "delete_node doesn't die when deleting an existing node" );
    is( $wiki->retrieve_node("A Node"), "",
	"...and retrieving a deleted node returns the empty string" );
    ok( ! $wiki->node_exists("A Node"),
	    "...and ->node_exists now returns false" );

    # Test deletion of a nonexistent node.
    eval { $wiki->delete_node("idonotexist") };
    is( $@, "",
	"delete_node doesn't die when deleting a non-existent node" );
}
