#!/usr/bin/perl

# syntactic transfer between chunks
# inter_transfer file format:
# 1. Reference chunk condition:
#	Selects the reference (my) chunk to transfer information from(up) or to(down)
# 2. Reference chunk attribute:
#	Which attribute to transfer(up) or to add/update(down).
# 3. Related chunk condition:
#	Restricts the related chunk to transfer information from(down) or to(up).
# 4. Related chunk attribute:
#	Which attribute to transfer(down) or to add/update(up).
# 5. Direction:
#	In which direction the information is propagated, i.e.
#	down or up the tree
# 6. Write mode:
#	Can be one of three, either:
#	no-overwrite (do not overwrite previous information),
#	overwrite (overwrite previous information),
#	concat (concatenate information to any previously existing).

# 1			2		3		4		5		6
# descendantCond	descendantAttr	ancestorCond	ancestorAttr	direction	writeMode

use strict;
use utf8;
use Storable; # to retrieve hash from disk
use open ':utf8';
#binmode STDIN, ':utf8';
#binmode STDOUT, ':utf8';
use XML::LibXML;
require "util.pl";

# retrieve hash with config parameters from disk
my %hash;
eval
{
	%hash = %{ retrieve("parameters") }; 
} or die "No parameters defined. Run readConfig.pl first!";

my $synTransInterFile= $hash{"STInterTransferFile"} or die "STInterTransferFile (syntactic transfer between nodes within a chunk) not specified in config!";
open STINTERFILE, "< $synTransInterFile" or die "Can't open $synTransInterFile : $!";

#print STDERR "$synTransInterFile\n";

my %interConditions;

#read syntactic transfer information from file into an array with inter chunk conditions
while(<STINTERFILE>) {
 	chomp;
 	s/#.*//;     # no comments
	s/^\s+//;    # no leading white
	s/\s+$//;    # no trailing white
	next if /^$/;   # skip if empty line
	my ($chunk1Cond, $chunk1Attr ,$chunk2Cond, $chunk2Attr, $path1to2, $direction, $wmode ) = split( /\s*\t\s*/, $_, 7 );
	#print STDERR "chunk1 condition: $chunk1Cond; attribute: $chunk1Attr;\nchunk2 condition: $chunk2Cond; attribute: $chunk2Attr; path: $path1to2;\ndir: $direction; mode: $wmode\n\n";
	$chunk1Cond =~ s/\s//g;
	$chunk2Cond =~ s/\s//g;
	my $condKey = "$chunk1Cond\t$chunk2Cond\t$path1to2";
	$interConditions{$condKey} = $chunk1Attr."\t".$chunk2Attr."\t".$direction."\t".$wmode;
}

close STINTERFILE;

#read xml from STDIN
my $parser = XML::LibXML->new("utf8");
my $dom    = XML::LibXML->load_xml( IO => *STDIN );

foreach my $chunk ( $dom->getElementsByTagName('CHUNK') ) {
	#print STDERR "chunk ". $chunk->getAttribute('ref'). " of type " . $chunk->getAttribute('type')."\n";
	foreach my $condpair (keys %interConditions) {
		my ($chunk1Cond,$chunk2Cond,$path1to2) = split( /\t/, $condpair);
#		print STDERR "$chunk1Cond ++ $chunk2Cond\n";
		#check chunk 1 conditions
		my @chunk1Conditions = &splitConditionsIntoArray($chunk1Cond);
#		print STDERR "$chunk1Cond\n";
		my $result = &evalConditions(\@chunk1Conditions,$chunk);
#		print STDERR "result $result\n";
		if ($result) {
			# find chunk candidates related to the current chunk
			my @candidates = &getRelatedChunks($chunk,$path1to2);
			#print STDERR scalar(@candidates). " candidates\n";
			if (scalar(@candidates)) {
				print STDERR "first chunk candidate ". $candidates[0]->getAttribute('ref')."\n";
				my @chunk2Conditions = &splitConditionsIntoArray($chunk2Cond);
				print STDERR "conditions: @chunk2Conditions\n";
				# find the first candidate related chunk that satisfies the conditions
				foreach my $cand (@candidates) {
					my $result = &evalConditions(\@chunk2Conditions,$cand);
					print STDERR "result $result for candidate ". $cand->getAttribute('ref')."\n";
					if ($result) {
						print STDERR "found\n";
						my $configline = $interConditions{$condpair};
						&transferSyntInformation($configline,$chunk,$cand);
					}
				}
			}
		}
	}
}

# print new xml to stdout
my $docstring = $dom->toString;
print STDOUT $docstring;

sub transferSyntInformation{
	my $configline = $_[0];
	my $chunk1 = $_[1];
	my $chunk2   = $_[2];

	my ($chunk1Attr,$chunk2Attr,$direction,$wmode) = split(/\t/,$configline);
	print STDERR "direction $direction\n";
	if ($direction eq "1to2") {
		&propagateAttr($chunk1,$chunk1Attr,$chunk2,$chunk2Attr,$wmode);
	}
	elsif ($direction eq "2to1") {
		&propagateAttr($chunk2,$chunk2Attr,$chunk1,$chunk1Attr,$wmode);	# switch src and trg
	}
	else {
		die "wrong propagation direction \"$direction\"";
	}
}

sub propagateAttr{
	my $srcNode = $_[0];
	my $srcAttr = $_[1];
	my $trgNode = $_[2];
	my $trgAttr = $_[3];
	my $wmode = $_[4];

	my $srcVal = $srcNode->getAttribute($srcAttr);
	if ($srcVal eq '') {
		$srcVal = $srcAttr;
	}
	$srcVal =~ s/["]//g;
	if ($wmode eq "concat") {
		my $newVal = $trgNode->getAttribute($trgAttr).",".$srcVal;
		$trgNode->setAttribute($trgAttr,$newVal);
	}
	elsif ($wmode eq "overwrite") {
		$trgNode->setAttribute($trgAttr,$srcVal);
	}
	elsif ($wmode eq "no-overwrite") {
		if ($trgNode->getAttribute($trgAttr)) {
			print STDERR "target node already has a value for the attribute ".$trgAttr."\n";
		}
		else {
#			print STDERR "$srcAttr => $trgAttr = $srcVal\n";
			$trgNode->setAttribute($trgAttr,$srcVal);
		}
	}
	else {
		die "wrong write mode \"$wmode\"";
	}
}

