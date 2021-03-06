#!/usr/bin/perl

# Configuration: NodeChunkFile
# 	nodes to be upgraded to chunks (to be reordered independently among other chunks)
# Format:
#	targetAttributes									sourceChunkAttrVal	targetChunkAttrVal
# Example:
# 	my.pos=/VMFIN/ && parent.pos=VV && chunkparent.type=/VP.*/ && !(chunkparent.si=subj)	nodechunk=finVerb	type=modalV
#
#
# Input: xml output from lexical transfer module from Matxin/Apertium (LT) after splitNodes.pl
#	example: <CHUNK type="VP" si="top"><NODE ... pos="VV"><NODE ... lem="müssen" pos="VMFIN" mi="3.Sg.Pres.Ind"></NODE></NODE></CHUNK>
# Output: TODO: update description!
# 	example: <CHUNK type="VP" si="top"><NODE ... pos="VV"/><CHUNK ... lem="müssen" pos="VMFIN" mi="3.Sg.Pres.Ind" type="modalV"></CHUNK></CHUNK>

use strict;

use utf8;
use open ':utf8';
use Storable; # to retrieve hash from disk
#binmode STDIN, ':utf8';
use XML::LibXML;
require "util.pl";

my %hash;
# retrieve hash with config parameters from disk, get path to file with semantic information
eval
{
	%hash = %{ retrieve("parameters") }; 
} or die "No parameters defined. Run readConfig.pl first!";

my $nodeChunkFile= $hash{"NodeChunkFile"} or die "NodeChunkFile not specified in config!";
open NODECHUNKFILE, "< $nodeChunkFile" or die "Can't open $nodeChunkFile : $!";

my %targetAttributes;
my %sourceAttributes;

# read the node conditions from file into a hash (origNodeCond, parentChunkCond, targetChunkAttrVal )
while(<NODECHUNKFILE>)
{
 	chomp;
 	s/#.*//;     # no comments
	s/^\s+//;    # no leading white
	s/\s+$//;    # no trailing white
	next if /^$/;	# skip if empty line
	my ($origNodeCond, $sourceChunkAttrVal, $targetChunkAttrVal ) = split( /\s*\t+\s*/, $_, 3 );
	$targetAttributes{$origNodeCond} = $targetChunkAttrVal;
	$sourceAttributes{$origNodeCond} = $sourceChunkAttrVal;

}

my $parser = XML::LibXML->new("utf8");
my $dom    = XML::LibXML->load_xml( IO => *STDIN );
my $maxChunkRef = &getMaxChunkRef($dom);

foreach my $node ( $dom->getElementsByTagName('NODE') ) {
	#get parent chunk
	my $parentChunk = &getParentChunk($node); 	#@{$node->findnodes('ancestor::CHUNK[1]')}[0]; # nearest ancestor chunk of node
	my $headNode = @{$parentChunk->findnodes('child::NODE')}[0];
	if (not $headNode->isSameNode($node)) { # is the head node equal the node to upgrade to a chunk?
		foreach my $nodeCond (keys %targetAttributes) {
			#check node conditions
			my @nodeConditions = &splitConditionsIntoArray($nodeCond);
			my $result = &evalConditions(\@nodeConditions,$node);
			if ($result) {
				# "upgrade" the NODE node to a CHUNK node
				print STDERR "upgrade " . $node->nodePath() . "(" . $node->getAttribute('slem') .") to a CHUNK\n";
				$node->unbindNode();
				my $newChunk = XML::LibXML::Element->new('CHUNK');
				$newChunk->appendChild($node);
				$parentChunk->appendChild($newChunk);
				my @sourceAttrs = split(",",$sourceAttributes{$nodeCond});
				foreach my $attrVal (@sourceAttrs) {
					my ($srcChunkAttr,$srcChunkVal) = split("=",$attrVal);
					$srcChunkVal =~ s/["]//g;
					$parentChunk->setAttribute($srcChunkAttr,$srcChunkVal);
				}
				my @attributes = split(",",$targetAttributes{$nodeCond});
				foreach my $attrVal (@attributes) {
					my ($newChunkAttr,$newChunkVal) = split("=", $attrVal);
					$newChunkVal =~ s/["]//g;
					$newChunk->setAttribute($newChunkAttr,$newChunkVal);
				}
				$maxChunkRef++;
				$newChunk->setAttribute('ref',"$maxChunkRef");
				$node->setAttribute('noderef',$node->getAttribute('ref'));	
			}
		}
	}
	#else {
	#	print STDERR "should the head node really be upgraded to a chunk?\n";
	#}
}

# print new xml to stdout
my $docstring = $dom->toString;
print STDOUT $docstring;


