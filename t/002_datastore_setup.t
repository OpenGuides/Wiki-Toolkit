use strict;
use Test::More tests => 15;
use CGI::Wiki;
use CGI::Wiki::TestConfig;

foreach my $dbtype (qw( MySQL Pg SQLite )) {

    SKIP: {
        skip "$dbtype backend not configured", 4
            unless $CGI::Wiki::TestConfig::config{$dbtype}->{dbname};

        my %config = %{$CGI::Wiki::TestConfig::config{$dbtype}};
        my $setup_class = "CGI::Wiki::Setup::$dbtype";
        eval "require $setup_class";
        {
            no strict 'refs';

            foreach my $method ( qw( cleardb setup ) ) {
                eval {
                    &{$setup_class . "::" . $method}(
                                   @config{ qw( dbname dbuser dbpass dbhost ) }
                                               );
                };
                is( $@, "",
                  "${setup_class}::$method doesn't die when called with list");

                eval {
                    &{$setup_class . "::" . $method}( \% config );
                };
                is( $@, "",
               "${setup_class}::$method doesn't die when called with hashref");
            }
        }
    }
}

SKIP: {
    skip "SQLite backend not configured", 3
        unless $CGI::Wiki::TestConfig::config{SQLite};

    my @mistakes = <HASH*>;
    is( scalar @mistakes, 0, "CGI::Wiki::Setup::SQLite doesn't create erroneous files called things like 'HASH(0x80fd394)'" );

    @mistakes = <ARRAY*>;
    is( scalar @mistakes, 0, "CGI::Wiki::Setup::SQLite doesn't create erroneous files called things like 'ARRAY(0x83563fc)'" );

    @mistakes = <4*>;
    is( scalar @mistakes, 0, "CGI::Wiki::Setup::SQLite doesn't create erroneous files called '4'" );
}
