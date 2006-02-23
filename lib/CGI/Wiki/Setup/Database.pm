package CGI::Wiki::Setup::Database;

use strict;

use vars qw( $VERSION );

$VERSION = 0.08;

=head1 NAME

CGI::Wiki::Setup::Database - parent class for database storage setup
classes for CGI::Wiki

=cut

# Fetch from the old style database, ready for an upgrade to db version 8
sub fetch_upgrade_old_to_8 {
	my $dbh = shift;
	my %nodes;
	my %metadatas;
	my %contents;
	my %ids;

	print "Grabbing and upgrading old data... ";

	# Grab all the nodes, and give them an ID
	my $sth = $dbh->prepare("SELECT name,version,text,modified FROM node");
	$sth->execute;
	my $id = 0;
	while( my($name,$version,$text,$modified) = $sth->fetchrow_array) {
		my %node;
		$id++;
		$node{'name'} = $name;
		$node{'version'} = $version;
		$node{'text'} = $text;
		$node{'modified'} = $modified;
		$node{'id'} = $id;
		$nodes{$name} = \%node;
		$ids{$name} = $id;
	}

	# Grab all the content, and upgrade to ID from name
	$sth = $dbh->prepare("SELECT name,version,text,modified,comment FROM content");
	$sth->execute;
	while ( my($name,$version,$text,$modified,$comment) = $sth->fetchrow_array) {
		my $id = $ids{$name};
		unless($id) { die("Couldn't find ID for name '$name'"); }
		my %content;
		$content{'id'} = $id;
		$content{'version'} = $version;
		$content{'text'} = $text;
		$content{'modified'} = $modified;
		$content{'comment'} = $comment;
		$contents{$id."-".$version} = \%content;
	}

	# Grab all the metadata, and upgrade to ID from node
	$sth = $dbh->prepare("SELECT node,version,metadata_type,metadata_value FROM metadata");
	$sth->execute;
	my $i = 0;
	while( my($node,$version,$metadata_type,$metadata_value) = $sth->fetchrow_array) {
		my $id = $ids{$node};
		unless($id) { die("Couldn't find ID for name/node '$node'"); }
		my %metadata;
		$metadata{'id'} = $id;
		$metadata{'version'} = $version;
		$metadata{'metadata_type'} = $metadata_type;
		$metadata{'metadata_value'} = $metadata_value;
		$metadatas{$id."-".($i++)} = \%metadata;
	}

	print "done\n";

	# Return it all
	return (\%nodes,\%contents,\%metadatas,\%ids);
}


# Get the version of the database schema
sub get_database_version {
	my $dbh = shift;
	my $sql = "SELECT version FROM schema_info";
	my $sth;
	eval{ $sth = $dbh->prepare($sql) };
	if($@) { return "old"; }
	eval{ $sth->execute };
	if($@) { return "old"; }

	my ($cur_schema) = $sth->fetchrow_array;
	unless($cur_schema) { return "old"; }

	return $cur_schema;
}

# Is an upgrade to the database required?
sub get_database_upgrade_required {
	my ($dbh,$VERSION) = @_;

	# Get the schema version
	my $schema_version = get_database_version($dbh);

	# Compare it
	my $new_ver = $VERSION * 100;
	if($schema_version eq $new_ver) {
		# At latest version
		return undef;
	} else {
		return $schema_version."_to_".$new_ver;
	}
}


# Put the latest data into the latest database structure
sub bulk_data_insert {
	my ($dbh, $nodesref, $contentsref, $metadataref) = @_;

	print "Bulk inserting upgraded data... ";

	# Add nodes
	my $sth = $dbh->prepare("INSERT INTO node (id,name,version,text,modified) VALUES (?,?,?,?,?)");
	foreach my $name (keys %$nodesref) {
		my %node = %{$nodesref->{$name}};
		$sth->bind_param(1, $node{'id'});
		$sth->bind_param(2, $node{'name'});
		$sth->bind_param(3, $node{'version'});
		$sth->bind_param(4, $node{'text'});
		$sth->bind_param(5, $node{'modified'});
		$sth->execute;
	}

	# Add content
	$sth = $dbh->prepare("INSERT INTO content (node_id,version,text,modified,comment) VALUES (?,?,?,?,?)");
	foreach my $key (keys %$contentsref) {
		my %content = %{$contentsref->{$key}};
		$sth->bind_param(1, $content{'id'});
		$sth->bind_param(2, $content{'version'});
		$sth->bind_param(3, $content{'text'});
		$sth->bind_param(4, $content{'modified'});
		$sth->bind_param(5, $content{'comment'});
		$sth->execute;
	}

	# Add metadata
	$sth = $dbh->prepare("INSERT INTO metadata (node_id,version,metadata_type,metadata_value) VALUES (?,?,?,?)");
	foreach my $key (keys %$metadataref) {
		my %metadata = %{$metadataref->{$key}};
		$sth->bind_param(1, $metadata{'id'});
		$sth->bind_param(2, $metadata{'version'});
		$sth->bind_param(3, $metadata{'metadata_type'});
		$sth->bind_param(4, $metadata{'metadata_value'});
		$sth->execute;
	}

	print "done\n";
}
