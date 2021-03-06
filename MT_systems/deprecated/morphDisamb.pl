#!/usr/bin/perl

# disambiguate morphologically ambigous translations
# path to morphologic/pos disambiguation file is expected to be included in the config file
# format of morphologic disambigution file, tab separated:
# source-lemma target-morph/pos	condition (optional) probability (between 0-1, in case condition is not met or not given)
# example (Spanish lemma 'ebrio' can be translated into Quechua as 'machaq' (a drinker) or 'machasqa' (drunk))
# ebrio	my.mi=VRoot+Ag	my.smi=/NC/	0.3
# ebrio	my.mi=VRoot+Perf	my.smi=/AQ/ 0.7

use utf8;
use Storable;    # to retrieve hash from disk
use open ':utf8';
use XML::LibXML;
use strict;
use File::Spec::Functions qw(rel2abs);
use File::Basename;
my $path = dirname(rel2abs($0));
require "$path/util.pl";

# retrieve hash with config parameters from disk, get path to file with semantic information
eval {
	retrieve('parameters');
	
} or die "No parameters defined. Run readConfig.pl first!";

my %hash    = %{ retrieve("parameters") };
my $morphSelFile = $hash{"MorphSelFile"}
  or die "Morphological selection file not specified in config!";
open MORPHSELFILE, "< $morphSelFile" or die "Can't open $morphSelFile : $!";

my %morphSel = ();

#read semantic information from file into a hash (lemma, semantic Tag,  condition)
while (<MORPHSELFILE>) {
	chomp;
	s/^(\s)*#.*//;     # no comments
	s/^\s+//;    # no leading white
	s/\s+$//;    # no trailing white
	next if /^$/;	# skip if empty line
	my ( $srcNodeConds, $trgtMI, $keepOrDelete, $conditions, $prob ) = split( /\s*\t+\s*/, $_, 5 );

	$conditions =~ s/\s//g;	# no whitespace within condition
	# assure key is unique, use srcConds:trgts as key
	my $key = "$srcNodeConds---$trgtMI";
	#print STDERR "key: $key\n";
	my @value = ( $conditions, $keepOrDelete, $prob );
	$morphSel{$key} = \@value;

}
my @allNodeConditions = keys(%morphSel);
my $parser = XML::LibXML->new("utf8");
my $dom    = XML::LibXML->load_xml( IO => *STDIN );

	# get all nodes (NODE) with ambigous translations (SYN)
	foreach my $node ( $dom->getElementsByTagName('NODE')) 
	{
		my @SYNnodes = $node->getChildrenByLocalName('SYN');
		
		# create hash to store values of synonyms of this particular node
		my %nodehash =();
		
		# if this node has SYN nodes,
		# check if one of the node conditions apply to this node
		if(scalar(@SYNnodes)>0)
		{
			#print STDERR "Disambiguating morphological translation options in sentence: ".$node->findvalue('ancestor::SENTENCE/@ref')."\n";
			foreach my $ruleskey (@allNodeConditions)
				{				
					my ($nodeCond, $trgtMI) = split('---',$ruleskey);		  
					my @nodeConditions = &splitConditionsIntoArray($nodeCond);

					# evaluate all head condition(s), if true for this node, check if the childnode conditions apply
					if(&evalConditions(\@nodeConditions,$node))
					{ 
							# check for each target conditions if one of the matching rules applies
							# if yes, check if k=keep or d=delete 
							# -> if keep, keep all matching SYN nodes and delete all the other SYN nodes
							# -> if delete, delete all matching SYN nodes
							
							# get target conditions
							my $trgtConds = @{ $morphSel{$ruleskey}}[0];
							my @trgtConditions = &splitConditionsIntoArray($trgtConds);
							#print STDERR "target conds: @trgtConditions\n";
							
							if(&evalConditions(\@trgtConditions,$node))
							{
								#keep or delete?
								my $keepOrDelete = @{ $morphSel{$ruleskey}}[1];
								my @targetMIs = split(',',$trgtMI);
								my @matchingSyns=();
								foreach my $trgt (@targetMIs)
								{
										# create xpath string to find matching synonyms:
										# NOTE: as this may not be the first rule to be applied, its possible that the values in $node belong to a SYN that has already been deleted,
										# if this was a rule with 'k' -> check also if node itself matches!
										my $xpathstring;
										my $selfXpathString;
										if($trgt !~ /=/)
										{ 
											$xpathstring= 'child::SYN[@mi="'.$trgt.'"]';
											$selfXpathString = 'self::NODE[@mi="'.$trgt.'"]';
										}
										#if other attribute than mi should be used for disambiguation
										else
										{ 
											my ($attr,$value) = split('=',$trgt);
											$xpathstring= 'child::SYN[@'.$attr.'="'.$value.'"]';
											$selfXpathString= 'self::NODE[@'.$attr.'="'.$value.'"]';
										}
										#print STDERR "xpath: $xpathstring\n";
										# find synnode with this 'mi', can be more than one
										my @matchingSynsCand = $node->findnodes($xpathstring);
										my @matchingSynsCand2 = $node->findnodes($selfXpathString);
										push(@matchingSyns,@matchingSynsCand);
										push(@matchingSyns,@matchingSynsCand2);
										
									}
									if(scalar(@matchingSyns)>0)
									{ 
											my $matchingtranslation = @matchingSyns[0];
											my @matchingtranslationAttributes = $matchingtranslation->attributes();
											#foreach my $m (@matchingSyns){print STDERR "match for $ruleskey:".$m->toString()."\n";}
									
								 		   	if($keepOrDelete eq 'k')
								   			{
								    			# delete the attributes of the first SYN child that have been "copied" into the parent NODE
												#my $firstsyn = $SYNnodes[0];
												my @synattrlist = $node->attributes();
												foreach my $synattr (@synattrlist)
												{
													unless($synattr->nodeName =~ /ref|slem|smi|sform|UpCase|sem/)
													{
														$node->removeAttribute($synattr->nodeName);
													}
												}
												# fill in attributes of best translation
												@SYNnodes = $node->getChildrenByLocalName('SYN');
								    			foreach my $bestattr (@matchingtranslationAttributes)
								    			{
								    				my $value = $bestattr->value;
								    				my $attr = $bestattr->nodeName;
								    				$node->setAttribute($attr, $value);
								    				
								    				
								    			}
								    			#delete all SYN nodes that did not match
								    			foreach my $syn (@SYNnodes)
								    			{
								    				unless( grep( $_ == $syn, @matchingSyns ))
								    				{   
								    					$node->removeChild($syn);
								    				}
								    			}
								    			#delete SYN node whose attributes have been copied to node
								    			#$node->removeChild($matchingtranslation);
								   			}
								   			elsif($keepOrDelete eq 'd')
								   			{
								   				# get all syn nodes, copy attributes of first syn that is NOT in matching translations
								   				# to NODE, delete all that are in @matchingtranslations, unless there is non left
								   				# in this case: keep last syn and print warning to STDERR
								   				# note: this is the morphological disambiuation -> keep sem attribute (no lexical differences in SYN's disambiguated here!)
													my @synattrlist = $node->attributes();
													foreach my $synattr (@synattrlist)
													{#print "attribute to remove in node ".$synattr->nodeName."\n";
														unless($synattr->nodeName =~ /^ref|slem|smi|sform|UpCase|sem/)
														{#print "removed attribute ".$synattr->nodeName."\n";
															$node->removeAttribute($synattr->nodeName);
														}
													}
													# fill in attributes of first SYN that is not in matchingtranslations
													my @SYNnodes = $node->getChildrenByLocalName('SYN');
								    				foreach my $syn (@SYNnodes)
								    				{
								    					if(!grep( $_ == $syn, @matchingSyns ) or $syn == @SYNnodes[-1])
								    					{ #print STDERR "inserted in node:".$syn->toString."\n";
								    						my @Attributes = $syn->attributes();
								    						foreach my $synattr (@Attributes)
								    						{
								    							my $value = $synattr->value;
								    							my $attr =	$synattr->nodeName;
								    							$node->setAttribute($attr, $value);
								    						}
								    						last;
								    					}
								    				}
								    				# if ALL syn nodes match: do not remove them! 
								    				unless(scalar(@matchingSyns) >= scalar(@SYNnodes)){
										   				#remove all matching translations:
										   				foreach my $matchingtranslation (@matchingSyns)
										   				{	#print STDERR "delete: ".$matchingtranslation->toString()."\n";
										   					#my $docstring = $dom->toString;
															#print STDERR $docstring;
										   					$node->removeChild($matchingtranslation);
										   				}
								    				}
								    		}
								   			else
								   			{
								    			print STDERR "error: invalid option $keepOrDelete! Valid options are: k (keep) or d (delete). Won't disambiguate.";
								   			 }
								   			 
										}
										
									}
							}
						
					}
			}
			# if this node has only one SYN child left (when all other SYNs have been deleted)
			# -> delete, as SYN is already contained in NODE
			# TODO: check if there's a SYN that is already in NODE -> delete
			my @remainingSYNs = $node->findnodes('child::SYN');
			if(scalar(@remainingSYNs) == 1 && @remainingSYNs[0]->getAttribute('lem') eq $node->getAttribute('lem') && @remainingSYNs[0]->getAttribute('mi') eq $node->getAttribute('mi') )
			{
				$node->removeChild(@remainingSYNs[0]);
			}
	}

# print new xml to stdout
my $docstring = $dom->toString;
print STDOUT $docstring;
