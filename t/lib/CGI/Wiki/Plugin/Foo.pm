package CGI::Wiki::Plugin::Foo;
use base qw( CGI::Wiki::Plugin );

sub new {
    my $class = shift;
    return bless {}, $class;
}

1;
