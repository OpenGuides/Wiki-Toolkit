use strict;
use CGI::Wiki::TestLib;
use Test::More;

if ( scalar @CGI::Wiki::TestLib::wiki_info == 0 ) {
    plan skip_all => "no backends configured";
} else {
    plan tests => ( 17 * scalar @CGI::Wiki::TestLib::wiki_info );
}

my $iterator = CGI::Wiki::TestLib->new_wiki_maker;

while ( my $wiki = $iterator->new_wiki ) {
    SKIP: {
        eval { require Test::MockObject; };
        skip "Test::MockObject not installed", 9 if $@;

        my $null_plugin = Test::MockObject->new;

        my $plugin = Test::MockObject->new;
        $plugin->mock( "on_register",
                       sub {
                           my $self = shift;
                           $self->{__registered} = 1;
                           $self->{__seen_nodes} = [ ];
                           $self->{__deleted_nodes} = [ ];
                           $self->{__moderated_nodes} = [ ];
                           }
                      );
        eval { $wiki->register_plugin; };
        ok( $@, "->register_plugin dies if no plugin supplied" );
        eval { $wiki->register_plugin( plugin => $null_plugin ); };
        is( $@, "",
     "->register_plugin doesn't die if plugin which can't on_register supplied"
          );
        eval { $wiki->register_plugin( plugin => $plugin ); };
        is( $@, "",
       "->register_plugin doesn't die if plugin which can on_register supplied"
          );
        ok( $plugin->{__registered}, "->on_register method called" );

        my @registered = $wiki->get_registered_plugins;
        is( scalar @registered, 2,
            "->get_registered_plugins returns right number" );
        ok( ref $registered[0], "...and they're objects" );

        my $regref = $wiki->get_registered_plugins;
        is( ref $regref, "ARRAY", "...returns arrayref in scalar context" );


		# Test the post_write (adding/updating a node) plugin call
        $plugin->mock( "post_write",
						sub {
							my ($self, %args) = @_;
							push @{ $self->{__seen_nodes} },
							{ node     => $args{node},
							  node_id  => $args{node_id},
							  version  => $args{version},
							  content  => $args{content},
							  metadata => $args{metadata}
							};
						}
        );

        $wiki->write_node( "Test Node", "foo", undef, {bar => "baz"} )
            or die "Can't write node";
        ok( $plugin->called("post_write"), "->post_write method called" );

        my @seen = @{ $plugin->{__seen_nodes} };
        is_deeply( $seen[0], { node => "Test Node",
                               node_id => 1,
                               version => 1,
                               content => "foo",
                               metadata => { bar => "baz" } },
                   "...with the right arguments" );



		# Test the post_delete (deletion) plugin call
        $plugin->mock( "post_delete",
						sub {
							my ($self, %args) = @_;
							push @{ $self->{__deleted_nodes} },
							{ node     => $args{node},
							  node_id  => $args{node_id},
							  version  => $args{version},
							};
						}
        );


		# Delete with a version
        $wiki->delete_node( name=>"Test Node", version=>1 )
            or die "Can't delete node";
        ok( $plugin->called("post_delete"), "->post_delete method called" );

        my @deleted = @{ $plugin->{__deleted_nodes} };
        is_deeply( $deleted[0], { node => "Test Node",
                               node_id => 1,
                               version => undef },
                   "...with the right arguments" );
        $plugin->{__deleted_nodes} = [];


		# Now add a two new versions
		my %node = $wiki->retrieve_node("Test Node 2");
        $wiki->write_node( "Test Node 2", "bar", $node{checksum} )
            or die "Can't write second version node";
		%node = $wiki->retrieve_node("Test Node 2");
        $wiki->write_node( "Test Node 2", "foofoo", $node{checksum} )
            or die "Can't write second version node";

		# Delete newest with a version
        $wiki->delete_node( name=>"Test Node 2", version=>2 )
            or die "Can't delete node";
        ok( $plugin->called("post_delete"), "->post_delete method called" );

        @deleted = @{ $plugin->{__deleted_nodes} };
        is_deeply( $deleted[0], { node => "Test Node 2",
                               node_id => 2,
                               version => 2 },
                   "...with the right arguments" );

		# And delete without a version
        $wiki->delete_node( name=>"Test Node 2" )
            or die "Can't delete node";
        ok( $plugin->called("post_delete"), "->post_delete method called" );

        @deleted = @{ $plugin->{__deleted_nodes} };
        is_deeply( $deleted[1], { node => "Test Node 2",
                               node_id => 2,
                               version => undef },
                   "...with the right arguments" );


		# Test the moderation plugin
        $plugin->mock( "post_moderate",
						sub {
							my ($self, %args) = @_;
							push @{ $self->{__moderated_nodes} },
							{ node     => $args{node},
							  node_id  => $args{node_id},
							  version  => $args{version},
							};
						}
        );

		# Moderate
        $wiki->moderate_node( name=>"Test Node 2", version=>2 )
            or die "Can't moderate node";
        ok( $plugin->called("post_moderate"), "->post_moderate method called" );

        my @moderated = @{ $plugin->{__moderated_nodes} };
        is_deeply( $deleted[0], { node => "Test Node 2",
                               node_id => 2,
                               version => 2 },
                   "...with the right arguments" );
    }
}
