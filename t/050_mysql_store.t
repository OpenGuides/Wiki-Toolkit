#!/usr/bin/perl -w

use strict;
use Test::More tests => 10;
use CGI::Wiki::TestConfig;

my $class;
BEGIN {
    $class = "CGI::Wiki::Store::MySQL";
    use_ok($class);
}

eval { $class->new; };
ok( $@, "Failed creation dies" );

my %config = %{$CGI::Wiki::TestConfig::config{MySQL}};
my ($dbname, $dbuser, $dbpass, $dbhost) =
                                      @config{qw(dbname dbuser dbpass dbhost)};

SKIP: {
    skip "No MySQL database configured for testing", 8 unless $dbname;

    my $store = eval { $class->new( dbname => $dbname,
				    dbuser => $dbuser,
				    dbpass => $dbpass,
				    dbhost => $dbhost );
		     };
    is( $@, "", "Creation succeeds" );
    isa_ok( $store, $class );
    ok( $store->dbh, "...and has set up a database handle" );

    # White box test - do internal locking functions work the way we expect?
    my $evil_store = $class->new( dbname => $dbname,
				  dbuser => $dbuser,
				  dbpass => $dbpass,
				  dbhost => $dbhost  );

    ok( $store->_lock_node("Home"), "Can lock a node" );
    ok( ! $evil_store->_lock_node("Home"),
        "...and now other people can't get a lock on it" );
    ok( ! $evil_store->_unlock_node("Home"),
        "...or unlock it" );
    ok( $store->_unlock_node("Home"), "...but I can unlock it" );
    ok( $evil_store->_lock_node("Home"),
	"...and now other people can lock it" );

    # Cleanup (not necessary, since this thread is about to die, but here
    # in case I forget and add some more tests at the end).
    $evil_store->_unlock_node("Home");

}
