package Wiki::Toolkit::Feed::Listing;

use strict;

=head1 NAME

Wiki::Toolkit::Feed::Listing - parent class for Feeds from Wiki::Toolkit.

Handles common data fetching tasks, so that child classes need only
worry about formatting the feeds.

Also enforces some common methods that must be implemented.

=cut


=item B<fetch_recently_changed_nodes>

Based on the supplied criteria, fetch a list of the recently changed nodes

=cut
sub fetch_recently_changed_nodes {
    my ($self, %args) = @_;

    my $wiki = $self->{wiki};

    my %criteria = (
                   ignore_case => 1,
                   );

    # If we're not passed any parameters to limit the items returned, 
    #  default to 15.
    $args{days} ? $criteria{days}           = $args{days}
                : $criteria{last_n_changes} = $args{items} || 15;
  
    $criteria{metadata_wasnt} = { major_change => 0 }     if $args{ignore_minor_edits};
    $criteria{metadata_was}   = $args{filter_on_metadata} if $args{filter_on_metadata};

    my @changes = $wiki->list_recent_changes(%criteria);

    return @changes;
}

=item B<fetch_oldest_for_recently_changed>

Based on the supplied criteria (but not using all of those used by
B<fetch_recently_changed_nodes>), find the newest node from the recently
changed nodes set. Normally used for dating the whole of a Feed.

=cut
sub fetch_newest_for_recently_changed {
    my ($self, %args) = @_;

    my %criteria = (ignore_case => 1);

    $args{days} ? $criteria{days}           = $args{days}
                : $criteria{last_n_changes} = $args{items} || 15;

    $criteria{metadata_wasnt} = { major_change => 0 }     if $args{ignore_minor_edits};
    $criteria{metadata_was}   = $args{filter_on_metadata} if $args{filter_on_metadata};

    my @changes = $self->{wiki}->list_recent_changes(%criteria);

    return $changes[0];
}


=item B<fetch_node_all_versions>

For a given node (name or ID), return all the versions there have been,
including all metadata required for it to go into a "recent changes"
style listing.

=cut
sub fetch_node_all_versions {
    my ($self, %args) = @_;

    # Check we got the right options
    unless($args{'name'}) {
        return ();
    }

    # Do the fetch
    my @nodes = $self->{wiki}->list_node_all_versions(
                        name => $args{'name'},
                        with_content => 0,
                        with_metadata => 1,
    );

    # Ensure that all the metadata fields are arrays and not strings
    foreach my $node (@nodes) {
        foreach my $mdk (keys %{$node->{'metadata'}}) {
            unless(ref($node->{'metadata'}->{$mdk}) eq "ARRAY") {
                $node->{'metadata'}->{$mdk} = [ $node->{'metadata'}->{$mdk} ];
            }
        }
    }

    return @nodes;
}


# The following are methods that any feed renderer must provide

=item B<recent_changes>
All implementing feed renderers must implement a method to fetch a list
of recent changes, and render them
=cut
sub recent_changes    { die("Not implemented by feed renderer!"); }
=item B<node_all_versions>
All implementing feed renderers must implement a method to fetch a list
of the different versions of a node, and render them
=cut
sub node_all_versions { die("Not implemented by feed renderer!"); }
=item B<feed_timestamp>
All implementing feed renderers must implement a method to produce a
feed specific timestamp, based on the supplied node
=cut
sub feed_timestamp    { die("Not implemented by feed renderer!"); }

1;
