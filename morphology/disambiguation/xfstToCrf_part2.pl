#!/usr/bin/perl

use strict;
use open ':utf8';
binmode STDIN, ':utf8';
binmode STDERR, ':utf8';
binmode STDOUT, ':utf8';
use Storable;

# check if paramenter was given, either:
# -train (disambiguated input, add class in last row)
# -test (input to be disambiguated, leave last row empty)


my $num_args = $#ARGV + 1;
if ($num_args > 2) {
  print STDERR "\nUsage:  perl xfstToCrf.pl -1/-2/-3 xfst_file (only with -1)\n";	
  print STDERR "-1: NS/VS, -2: nominal+verbal morph disamb, 3: independent suffixes disamb\n";	
  exit;
}

my $mode = $ARGV[0];
unless($mode eq '-1' or $mode eq '-2' or $mode eq '-3' or !$mode){
	print STDERR "\nUsage:  perl xfstToCrf.pl -1/-2/-3\n";	
 	print STDERR "-1: NS/VS, -2: nominal+verbal morph disamb, 3: independent suffixes disamb\n";	
  	exit;
}
if($mode == '-1'){
	my $xfst = $ARGV[1];
	open XFST, "< $xfst" or die "Can't open $xfst (need xfst file with option -1): $!";
}

elsif($mode == '-2' or $mode == '-3'){
	my $crf = $ARGV[1];
	open CRF, "< $crf" or die "Can't open $crf (need disambiguated crf file with option -2 or -3): $!";
}


my @words;
my $newWord=1;
my $index=0;

if($mode eq '-1')
{
	while(<XFST>)
	{
		
		if (/^$/)
		{
			$newWord=1;
		}
		else
		{	
			my ($form, $analysis) = split(/\t/);
		
			my ($pos) = $analysis =~ m/(ALFS|CARD|NP|NRoot|Part|VRoot|PrnDem|PrnInterr|PrnPers|SP|\$)/ ;
			
			my ($root) = $analysis =~ m/^([^\[]+?)\[/ ;
			#print "$root\n";
			
			if($pos eq ''){
				if($form eq '#EOS'){
					$pos = '#EOS';
				}
				else{
					$pos = "ZZZ";
				}
			}
			
			my @morphtags =  $analysis =~ m/(\+.+?)\]/g ;
			
			my $allmorphs='';
			foreach my $morph (@morphtags){
				$allmorphs = $allmorphs.$morph;
			}
		
			#print "allmorphs: $allmorphs\n";
			#print "morphs: @morphtags\n\n";
		
			#print "$form: $root morphs: @morphtags\n";
			my %hashAnalysis;
			$hashAnalysis{'pos'} = $pos;
			$hashAnalysis{'morph'} = \@morphtags;
			$hashAnalysis{'string'} = $_;
			$hashAnalysis{'root'} = $root;
	    	$hashAnalysis{'allmorphs'} = $allmorphs;
	    
			if($newWord)
			{
				my @analyses = ( \%hashAnalysis ) ;
				my @word = ($form, \@analyses);
				push(@words,\@word);
				$index++;
			}
			else
			{
				my $thisword = @words[-1];
				my $analyses = @$thisword[1];
				push(@$analyses, \%hashAnalysis);
			}
			$newWord=0;	
	 }
		
	}
	close XFST;
	my $disambiguatedForms=0;
	# if a word has more than one analysis that differ only in length of the root by 1, and last letter is -q/-y/-n 
	# delete the one with the shorter root (e.g. millay -> milla -y/millay, qapaq-> qapa-q/qapaq, allin -> alli -n/ allin)
	foreach my $word (@words)
	{
		
		my $analyses = @$word[1];
		my $form = @$word[0];
		
		if(scalar(@$analyses)>1)
		{
			for(my $j=0;$j<scalar(@$analyses);$j++) 
			{
				my $analysis = @$analyses[$j];
				my $root = $analysis->{'root'};
				#print "$root ";
				#check if contained in following roots
				for(my $k=$j+1;$j<$k;$k--) 
				{
					my $analysis = @$analyses[$k];
					my $postroot = $analysis->{'root'};
					#print "$postroot ";
					if($postroot =~ /\Q$root\E[yqn]$/)
					{
						splice (@{$analyses},$j,1);	
						$j--;
						$disambiguatedForms++;
						#print "1 to delete $root, compared with $postroot\n";
						last;	
					}
					elsif($root eq 'u' && $postroot eq 'o')
					{
						splice (@{$analyses},$j,1);	
						$j--;
						$disambiguatedForms++;
						#print "1 to delete $root, compared with $postroot\n";
						last;	
					}
					else
					{
						#check if contained in preceding roots
						for(my $k=0;$k<$j;$k++) 
						{
							my $analysis = @$analyses[$k];
							my $preroot = $analysis->{'root'};
							#print "2 $root vs. $preroot \n";
							if($preroot =~ /\Q$root\E[yqn]$/)
							{
								splice (@{$analyses},$j,1);	
								$j--;
								$disambiguatedForms++;
								#print "2 to delete $root, compared with $preroot\n";
							}
							elsif($root eq 'u' && $preroot eq 'o')
							{
								splice (@{$analyses},$j,1);	
								$j--;
								$disambiguatedForms++;
								#print "2 to delete $root, compared with $postroot\n";
								last;	
							}
						}
					}
				}
				
				# if analysis differ in -kama +Dist vs. +Term -> take +Term, delete +Dist
				my $morphs = $analysis->{'morph'};
				#print "@$morphs\n";
				if(grep {$_ =~ /Dist/} @$morphs){
					# check if later analysis has +Term
					for(my $k=$j+1;$j<$k;$k--) 
					{
						my $analysis = @$analyses[$k];
						my $postmorphs = $analysis->{'morph'};
						if(grep {$_ =~ /Term/} @$postmorphs){
							splice (@{$analyses},$j,1);	
							$disambiguatedForms++;
							$j--;
							#print "2 to delete @$morphs\n";
							#print "compared with @$postmorphs\n";
							last;
						}
					}
					# check if previuous analysis has +Term
					for(my $k=0;$k<$j;$k++) 
					{
						my $analysis = @$analyses[$k];
						my $premorphs = $analysis->{'morph'};
						if(grep {$_ =~ /Term/} @$premorphs){
							splice (@{$analyses},$j,1);	
							$disambiguatedForms++;
							$j--;
							#print "2 to delete @$morphs\n";
							#print "compared with @$premorphs\n";
							last;
						}
					}
				}
				
				#print "\n";
			}
		}
	}
	#print "prev: $disambiguatedForms\n";
	store \$disambiguatedForms, 'prevdisambMorph1';

	# get NS / VS ambiguities
	foreach my $word (@words)
	{
		my $analyses = @$word[1];
		my @possibleClasses = ();
		
		if(scalar(@$analyses)>1)
		{
			# VERBAL morphology
			# -sqayki
			if(&containedInOtherMorphs($analyses,"+Perf","+1.Sg.Subj_2.Sg.Obj.Fut"))
			{
				push(@possibleClasses, "Perf");
				push(@possibleClasses, "Fut");
				if(&containedInOtherMorphs($analyses,"+Perf","+IPst+1.Sg.Subj_2.Sg.Obj")){
					push(@possibleClasses, "IPst");
				}
				#push(@ambWords,$word);
				push(@$word, "amb");
				#print "@$word[0]\n";
			}
			# -sqaykichik
			elsif(&containedInOtherMorphs($analyses,"+Perf","+1.Sg.Subj_2.Pl.Obj.Fut"))
			{
				push(@possibleClasses, "Perf");
				push(@possibleClasses, "Fut");
				if(&containedInOtherMorphs($analyses,"+Perf","+IPst+1.Sg.Subj_2.Pl.Obj")){
					push(@possibleClasses, "IPst");
				}
				#push(@ambWords,$word);
				push(@$word, "amb");
				#print "@$word[0]\n";
			}
			# -sqa
			elsif(&containedInOtherMorphs($analyses,"+Perf","+IPst") || &containedInOtherMorphs($analyses,"+Perf","+3.Sg.Subj.IPst") )
			{
				push(@possibleClasses, "IPst");
				push(@possibleClasses, "Perf");
				#push(@ambWords,$word);
				push(@$word, "amb");
				#print "@$word[0]\n";
			}
			# -y
			elsif(&containedInOtherMorphs($analyses,"+2.Sg.Subj.Imp","+Inf"))
			{
				push(@possibleClasses, "Imp");
				push(@possibleClasses, "Inf");
				#push(@ambWords,$word);
				push(@$word, "amb");
				#print "@$word[0]\n";
			}
			# -yman
			elsif(&containedInOtherMorphs($analyses,"+1.Sg.Subj.Pot","+Inf+Dat_Ill"))
			{
				push(@possibleClasses, "Pot");
				push(@possibleClasses, "Inf");
				#push(@ambWords,$word);
				push(@$word, "amb");
				#print "@$word[0]\n";
			}
			# -ykuna
			elsif(&containedInOtherMorphs($analyses,"+Inf+Pl","+Aff+Obl"))
			{
				push(@possibleClasses, "Inf");
				push(@possibleClasses, "Aff_Obl");
				#push(@ambWords,$word);
				push(@$word, "amb");
				#print "@$word[0]\n";
			}
#			# -nakuna
#			elsif(&containedInOtherMorphs($analyses,"+Obl+Pl","+Rzpr+Rflx_Int+Obl"))
#			{
#				push(@possibleClasses, "Obl_Pl");
#				push(@possibleClasses, "Rzpr_Rflx_Obl");
#			}
			# -kuna
			elsif(&containedInOtherMorphs($analyses,"+Pl","+Rflx_Int+Obl"))
			{
				push(@possibleClasses, "Pl");
				push(@possibleClasses, "Rflx_Obl");
				#push(@ambWords,$word);
				push(@$word, "amb");
				#print "@$word[0]\n";
			}
			# -cha
			elsif(&containedInOtherMorphs($analyses,"+Fact","+Dim"))
			{
				push(@possibleClasses, "Fact");
				push(@possibleClasses, "Dim");
				# should not be a verb, but you never know..
				if(&containedInOtherMorphs($analyses,"+Dim","+Vdim+Rflx_Int+Obl") or &containedInOtherMorphs($analyses,"+Fact","+Vdim") ){
					push(@possibleClasses, "Vdim");
				}
				#push(@ambWords,$word);
				push(@$word, "amb");
				#print "@$word[0]\n";
			}
			
			# else: other ambiguities, leave
			else
			{
				push(@possibleClasses, "ZZZ");
			}
		}
		# unambiguous forms: use pos tag, should help with context (hopefully)
		else
		{
			push(@possibleClasses, "ZZZ");
			#push(@possibleClasses, @$analyses[0]->{'pos'});
		}
		push(@$word, \@possibleClasses);
		#print @$word[0].": @possibleClasses\n";
		
	}
	# store @words to disk
	store \@words, 'words1';
#	store \@ambWords, 'ambWords';
	printCrf(\@words);
	
}

if($mode eq '-2')
{
	#retrieve words from disk
	my $wordsref = retrieve('words1');
	@words = @$wordsref;
	
	# disambiguate with crf file
	&disambMorph1(\@words);
	
	# get verbal / nominal ambiguities
	foreach my $word (@words){
		my $analyses = @$word[1];
		my @possibleClasses = ();
		
		if(scalar(@$analyses)>1)
		{
			# VERBAL morphology
			
			# -sun
			if(&containedInOtherMorphs($analyses,"+1.Pl.Incl.Subj.Imp","+1.Pl.Incl.Subj.Fut"))
			{
				push(@possibleClasses, "Imp");
				push(@possibleClasses, "Fut");
			}
			# -nqa
			elsif(&containedInOtherMorphs($analyses,"+3.Sg.Subj+Top","+3.Sg.Subj.Fut"))
			{
				push(@possibleClasses, "Top");
				push(@possibleClasses, "Fut");
			}
			# -sqaykiku
			elsif(&containedInOtherMorphs($analyses,"+IPst+1.Pl.Excl.Subj_2.Sg.Obj","+1.Pl.Excl.Subj_2.Sg.Obj.Fut"))
			{
				push(@possibleClasses, "IPst");
				push(@possibleClasses, "Fut");
			}
			# NOMINAL morphology
			# -nkuna
			elsif(&containedInOtherMorphs($analyses,"+3.Pl.Poss+Pl","+3.Sg.Poss+Pl"))
			{
				push(@possibleClasses, "Sg");
				push(@possibleClasses, "Pl");
			}
			# -ykuna
			elsif(&containedInOtherMorphs($analyses,"+1.Pl.Excl.Poss+Pl","+1.Sg.Poss+Pl"))
			{
				push(@possibleClasses, "Sg");
				push(@possibleClasses, "Pl");
			}
	
			# else: other ambiguities, leave
			else
			{
				push(@possibleClasses, "ZZZ");
			}
		}
		# unambiguous forms: use pos tag, should help with context (hopefully)
		else
		{
			push(@possibleClasses, "ZZZ");
			#push(@possibleClasses, @$analyses[0]->{'pos'});
		}
		push(@$word, \@possibleClasses);
		#print @$word[0].": @possibleClasses\n";
		
	}
	# store @words to disk
	store \@words, 'words2';
	printCrf(\@words);
}

if($mode eq '-3')
{
	#retrieve words from disk
	my $wordsref = retrieve('words2');
	@words = @$wordsref;
	
	# get ambiguities in independent suffixes
	foreach my $word (@words){
		my $analyses = @$word[1];
		my @possibleClasses = ();
		
		if(scalar(@$analyses)>1)
		{
			# -n
			if(&containedInOtherMorphs($analyses,"+DirE","+3.Sg.Poss") )
			{
				push(@possibleClasses, "DirE");
				push(@possibleClasses, "Poss");
			}
			# -pis
			elsif(&containedInOtherMorphs($analyses,"+Loc+IndE","+Add"))
			{
				push(@possibleClasses, "Loc_IndE");
				push(@possibleClasses, "Add");
			}
	
			# -s with Spanish roots: Plural or IndE (e.g. derechus)
			elsif(!&notContainedInMorphs($analyses, "+IndE"))
			{
				foreach my $analisis(@$analyses)
				{
					my $string = $analisis->{'string'};
					if($string =~ /s\[NRootES/  )
					{
						push(@possibleClasses, "Pl");
						push(@possibleClasses, "IndE");
					}
				}
				
			}
			# else: lexical ambiguities, leave
			else
			{
				push(@possibleClasses, "ZZZ");
			}
		}
		# unambiguous forms: use pos tag, should help with context (hopefully)
		else
		{
			push(@possibleClasses, "ZZZ");
			#push(@possibleClasses, @$analyses[0]->{'pos'});
		}
		push(@$word, \@possibleClasses);
		#print @$word[0].": @possibleClasses\n";
		
	}
	# store @words to disk
	store \@words, 'words3';
	printCrf(\@words);
}

my $lastlineEmpty=0;

# OLD print!
# print all words
#foreach my $word (@words){
#	my $analyses = @$word[1];
#	#my $analysis = @$analyses[0];
#	#print "pos:".$analysis->{'pos'}."\n";
#	#my $analysis2 = @$analyses[1];
#	#print $analysis2->{'pos'}."\n";
#	my $form = @$word[0];
#	my $possibleClasses = @$word[2];
#	
#	if($form eq '#EOS' ){
#		unless($lastlineEmpty == 1){
#			print "\n";
#			$lastlineEmpty =1;
#			next;
#		}
#	}
#	else
#	{
#		print "$form\t";
#		$lastlineEmpty =0;
#		# uppercase/lowercase?
#
##		elsif(substr($form,0,1) eq uc(substr($form,0,1))){
##			print "uc\t";
##		}
##		# lowercase
##		else{
##			print "lc\t";
##		}
#		print @$analyses[0]->{'pos'}."\t";
#
#
#		my $nbrOfClasses =0;
#		# possible classes
#		foreach my $class (@$possibleClasses){
#			print "$class\t";
#			$nbrOfClasses++;
#		}
#
#		while($nbrOfClasses<4){
#			print "ZZZ\t";
#			$nbrOfClasses++;
#		}
#		
#
#		#possible morph tags: take ALL morph tags into account 
#		my $printedmorphs='';
#		my $nbrOfMorph =0;
#		foreach my $analysis (@$analyses){
#			my $morphsref = $analysis->{'morph'};
#			#print $morphsref;
#			foreach my $morph (@$morphsref){
#			unless($printedmorphs =~ /\Q$morph\E/){
#			print "$morph\t";
#				$printedmorphs = $printedmorphs.$morph;
#				$nbrOfMorph++;
#				}
#			}
#		}
#		while($nbrOfMorph<10){
#			print "ZZZ\t";
#			$nbrOfMorph++;
#		}
#	
#		print "\n";
#	}
#}

sub printCrf{
#	my $wordsref = $_[0];
#	my @words = @$wordsref;
#	
#	for (my $i=0;$i<scalar(@words);$i++)
#	{
#		my $word = @words[$i];
#		my $analyses = @$word[1];
#		my $form = @$word[0];
#		my $possibleClasses = @$word[2];
#		my $correctClass = @$word[3];
#		
#	   if(scalar(@$possibleClasses)>1){
#	   		#push(@ambWords,$word);
#			print "$form\t";
#	
#			print @$analyses[0]->{'pos'}."\t";
#	
#			my $nbrOfClasses =0;
#			# possible classes
#			foreach my $class (@$possibleClasses){
#				print "$class\t";
#				$nbrOfClasses++;
#			}
#			
#			while($nbrOfClasses<4){
#				print "ZZZ\t";
#				$nbrOfClasses++;
#			}
#	
#			#possible morph tags: take ALL morph tags into account 
#			my $printedmorphs='';
#			my $nbrOfMorph =0;
#			foreach my $analysis (@$analyses){
#				my $morphsref = $analysis->{'morph'};
#				#print $morphsref;
#				foreach my $morph (@$morphsref){
#				unless($printedmorphs =~ /\Q$morph\E/){
#				print "$morph\t";
#					$printedmorphs = $printedmorphs.$morph;
#					$nbrOfMorph++;
#					}
#				}
#			}
#			while($nbrOfMorph<10){
#				print "ZZZ\t";
#				$nbrOfMorph++;
#			}
#		
#			# print context words (preceding)
#			for (my $j=$i-1;$j>($i-3);$j--)
#			{
#				my $word = @words[$j];
#				my $analyses = @$word[1];
#				my $form = @$word[0];
#				
#				print "$form\t";
#				print @$analyses[0]->{'pos'}."\t";
#				#print morphs of context words
#				my $printedmorphs='';
#				my $nbrOfMorph =0;
#				foreach my $analysis (@$analyses){
#					my $morphsref = $analysis->{'morph'};
#					#print $morphsref;
#					foreach my $morph (@$morphsref){
#					unless($printedmorphs =~ /\Q$morph\E/){
#					print "$morph\t";
#						$printedmorphs = $printedmorphs.$morph;
#						$nbrOfMorph++;
#						}
#					}
#				}
#				while($nbrOfMorph<10){
#					print "ZZZ\t";
#					$nbrOfMorph++;
#				}
#			}
#			
#			# print context words (following)
#			for (my $j=$i+1;$j<($i+3);$j++)
#			{
#				my $word = @words[$j];
#				my $analyses = @$word[1];
#				my $form = @$word[0];
#				
#				print "$form\t";
#				print @$analyses[0]->{'pos'}."\t";
#				#print morphs of context words
#				my $printedmorphs='';
#				my $nbrOfMorph =0;
#				foreach my $analysis (@$analyses){
#					my $morphsref = $analysis->{'morph'};
#					#print $morphsref;
#					foreach my $morph (@$morphsref){
#					unless($printedmorphs =~ /\Q$morph\E/){
#					print "$morph\t";
#						$printedmorphs = $printedmorphs.$morph;
#						$nbrOfMorph++;
#						}
#					}
#				}
#				while($nbrOfMorph<10){
#					print "ZZZ\t";
#					$nbrOfMorph++;
#				}
#			}
#			print "\n\n";
#		}
#	}
}



sub containedInOtherMorphs{
	my $analyses = $_[0];
	my $string1 = $_[1];
	my $string2 = $_[2];
	
	for(my $j=0;$j<scalar(@$analyses);$j++) 
	{
		my $analysis = @$analyses[$j];
		my $allmorphs = $analysis->{'allmorphs'};
		#print "morphs: $allmorphs  string: $string1\n";
		if($allmorphs =~ /\Q$string1\E/)
		{	
			# check if later analysis has +Term
			for(my $k=$j+1;$j<$k;$k--) 
			{
				my $analysis2 = @$analyses[$k];
				my $postmorphs = $analysis2->{'allmorphs'};
				#print "next: $postmorphs\n";
				if($postmorphs =~ /\Q$string2\E/ )
				{		
					#print "2 found $allmorphs\n";
					#print "2compared with $postmorphs\n";
					return 1;
				}
			}
			# check if previuous analysis has +Term
			for(my $k=0;$k<$j;$k++) 
			{
				my $analysis3 = @$analyses[$k];
				my $premorphs = $analysis3->{'allmorphs'};
				#print "prev: $premorphs\n";
				if($premorphs =~ /\Q$string2\E/)
				{
					#print "3 found $allmorphs\n";
					#print "3 compared with $premorphs\n";
					return 1;
				}
			}
		}
	}
	return 0;
}

sub notContainedInMorphs{
	my $analyses = $_[0];
	my $string = $_[1];
	
	foreach my $analysis (@$analyses)
	{
		my $allmorphs = $analysis->{'allmorphs'};
		if($allmorphs =~ /\Q$string\E/){
			return 0;
		}
	}
	return 1;
}

sub printXFST{
	my $wordsref = $_[0];
	my @words = @$wordsref;
	
	foreach my $word (@words){
		my $analyses = @$word[1];
		foreach my $analysis (@$analyses){
			print STDERR $analysis->{'string'};
		}
		print STDERR "\n";
	}
	
}

sub disambMorph1{
	my $wordsref = $_[0];
	my @words = @$wordsref;
	
	#retrieve ambwords from disk
	#my $ambwordsref = retrieve('ambWords');
	#@ambWords = @$ambwordsref;
	my @ambWords;
	foreach my $w (@words){
		# check if marked as ambiguous
		if(@$w[2] eq 'amb'){
			#print @$w[0]."\n";
			push(@ambWords, $w);
		}
		
	}
	
	my @crfLinesWithEmpty = <CRF>;

	# remove empty lines in crf file, then compare length to xfst (must be the same!)
	my @crfLines = grep {!/^$/} @crfLinesWithEmpty;

	#print "amb words ".scalar(@ambWords)."\n";
	#print "intern amb words ".scalar(@crfLines)."\n";
	#foreach my $line (@crfLines){print $line."\n";}
	
	# find differences in files
	for(my $i=0;$i<scalar(@ambWords);$i++){
		my $line = @crfLines[$i];
		my ($crfform, $rest) = split('\t',$line);
		
		my $ambword = @ambWords[$i];
		my $analyses = @$ambword[1];
		my $form = @$ambword[0];
		#print "$form $crfform\n";
		if($form ne $crfform ){
			unless($crfform =~ /^\s*$/){
			print STDERR "not the same word in line ".($i+1).": intern:$form, crf:$crfform\n";
			exit;
			}
		}
		#print "same word in line ".($i+1).": xfst:$form, crf:$crfform\n";
	}
	
	#my $last = @words[-1];
	#my $last2 = @words[-2];
	#print "last word in intern:".@$last[0]."\n";
	#print "prelast word in intern:".@$last2[0]."\n";
	
	my $unambigForms = 0;
	my $ambigForms = 0;
	my $stillambigForms =0;
	my $disambiguatedForms=0;
	
	my $ambIndex=0;
	
	for(my $i=0;$i<scalar(@words);$i++){
		my $word = @words[$i];
		my $analyses = @$word[1];
		my $form = @$word[0];
		
		if(scalar(@$analyses) > 1)
		{
			$ambigForms++;
		}
		else
		{
			$unambigForms++;
		}
		# only one analysis, print as is
#		if(scalar(@$analyses) == 1){
#			#print @$analyses[0]->{'string'}."\n";
#			$unambigForms++;
#		}
#		
#		else
#		{	
		# NEW: don't print, change @words and store to disk
		if(@$word[2] eq 'amb' && scalar(@$analyses) > 1)
		{
			# get valid pos from crf file 
			my $crfline = @crfLines[$ambIndex];
			$ambIndex++;
			my (@rows) = split('\t',$crfline);
			my $correctMorph = @rows[-1];
			#print "@rows[0] : $correctMorph\n"; #----- ".@$word[0]."\n";
			
			# possible root pos
			for(my $j=0;$j<scalar(@$analyses);$j++) {
				my $analysis = @$analyses[$j];
				my $allmorphs = $analysis->{'allmorphs'};
				
				# at this point, all the classes/tags are mutually exclusive, so we can just check whether the class is contained in allmorphs		
				# -sqayki: Perf, IPst, Fut
				# -sqaykichik: Perf, IPst, Fut
				# -sqa: Perf, IPst
				# -y: Inf, Imp
				# -yman: Inf, Pot
				# -ykuna: Inf, Aff_Obl
				# -kuna: Pl, Rflx_Obl
				# -cha: Fact, Dim
				if($allmorphs !~ /\Q$correctMorph\E/ && scalar(@$analyses) > 1){
					splice (@{$analyses},$j,1);	
					$disambiguatedForms++;
					$j--;		
				}
			}
	
			# for debugging: print disambiguated forms
#			for(my $j=0;$j<scalar(@$analyses);$j++) {
#				my $analysis = @$analyses[$j];
#					print @$analyses[$j]->{'string'};
#			}
			
		#	print "\n";
			
		}
		# for debugging: print only forms that are still ambiguous
		if(scalar(@$analyses) > 1){
					$stillambigForms++;
	#				for(my $j=0;$j<scalar(@$analyses);$j++) {
	#				my $analysis = @$analyses[$j];
	#				print @$analyses[$j]->{'string'};
	#			}
		}
	}
	# retrieve number of previously disambiguated forms ('rule' based, e.g +Dist/+Term, chiqan/chiqa etc.)
	my $prevdisamb = retrieve('prevdisambMorph1');
	#print "prev $$prevdisamb\n";
	
	# for testing: print xfst to STDERR
	#&printXFST(\@words);
	my $totalWords = scalar(@words);
	my $unamb = $unambigForms/$totalWords;
	my $amb = ($$prevdisamb + $ambigForms)/$totalWords;
	my $disamb = ($$prevdisamb + $disambiguatedForms)/$totalWords;
	my $stillamb = $stillambigForms/$ambigForms;
	$ambigForms = $$prevdisamb + $ambigForms;
	
	print STDERR "number of words: $totalWords\n"; 
	print STDERR "unambiguous forms: $unambigForms: "; printf STERR ("%.2f", $unamb); print STDERR "\n";
	print STDERR "ambiguous forms: $ambigForms: "; printf STDERR ("%.2f", $amb); print STDERR "\n";
	print STDERR "disambiguated with morph1: rules: $$prevdisamb, crf: $disambiguatedForms: "; printf STDERR ("%.2f", $disamb); print STDERR "\n";
	print STDERR "still ambiguous after morph1 disambiguation: $stillambigForms: $stillamb"; printf STDERR ("%.2f", $stillamb); print STDERR "\n";
	
	close CFG;
}
