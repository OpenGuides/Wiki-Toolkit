package Wiki::Toolkit::Feed::Listing;

use strict;

=head1 NAME

Wiki::Toolkit::Feed::Listing - parent class for Feeds from Wiki::Toolkit.

Handles common data fetching tasks, so that child classes need only
worry about formatting the feeds.

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

    # TODO. Will make use of store->list_node_all_versions()
}

1;
