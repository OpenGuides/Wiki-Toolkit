# Purpose: create, read, update, and delete a node with charset => UTF-8

use strict;
use Wiki::Toolkit::TestLib;
use Test::More;

if ( scalar @Wiki::Toolkit::TestLib::wiki_info == 0 ) {
    plan skip_all => "no backends configured";
} else {
    plan tests => 7 * scalar @Wiki::Toolkit::TestLib::wiki_info;
}

my $node_name = 'Whatever';
my $content   = 'ö';

my $iterator = Wiki::Toolkit::TestLib->new_wiki_maker;

while ( my $wiki = $iterator->new_wiki ) {
    my $store = $wiki->store;
    my ($db_engine) = ref($store) =~/([^:]+$)/;
    $store->{_charset} = 'UTF-8';

    # Test a simple write and retrieve.
    ok (eval { $wiki->write_node($node_name, $content) },
        "$db_engine: write_node with non-ASCII content" );
  SKIP: {
        if ($@) {
            diag substr($@,0,70) . " ...";
            skip "$db_engine: Node could not be written, skip retrieve and update tests", 6;
        }

        my $char_length = $store->dbh->selectrow_array(
            "SELECT LENGTH(text) FROM node WHERE name = '$node_name'" );
        is( $char_length, length($content),
            "$db_engine: Content has expected length" );

        my %node = $wiki->retrieve_node( $node_name );
        is( $node{content}, $content,
            "$db_engine: retrieve_node can retrieve it" );

        # Test ->node_exists.
        ok( $wiki->node_exists($node_name),
            "$db_engine: node_exists returns true for an existing node" );

        my $version  = $node{version} + 1;
        my $content  = "Version $version: $node{content}";
        my $checksum = $node{checksum};

        ok( $wiki->write_node($node_name, $content, $checksum),
            "$db_engine: Update successful");
        %node = $wiki->retrieve_node($node_name);

        is( $node{content}, $content,
            "$db_engine: Read after update provides correct content" );

        # Cleanup
        $wiki->delete_node(name => $node_name);
        ok( ! $wiki->node_exists($node_name),
            "$db_engine: node_exists returns false after deleting the node" );
    }
}
