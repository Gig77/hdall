use strict;
use warnings FATAL => qw( all );

use lib "/mnt/projects/hdall/scripts/lolliplot";
use lib "/mnt/projects/generic/scripts";

use Carp;
use Generic;
use Log::Log4perl qw(:easy);
use Getopt::Long;
use Lolliplot;

my ($hugos, $filtered_variants_file, $output_directory, $patients_list, $min_af);
GetOptions
(
	"hugos=s" => \$hugos, # HUGO gene symbols, e.g. CREBBP,KRAS,NRAS
	"filtered-variants=s" => \$filtered_variants_file, # file with filtered variants
	"patients=s" => \$patients_list, # if specified, consider mutations only from these patients
	"min-af=s" => \$min_af, # minimum allelic frequency
	"output-directory=s" => \$output_directory # output directory
);

die "ERROR: --hugos not specified\n" if (!$hugos);
die "ERROR: --filtered-variants not specified\n" if (!$filtered_variants_file);
die "ERROR: --output-directory not specified\n" if (!$output_directory);

my %patients_hash;
if ($patients_list)
{
	foreach (split(",", $patients_list))
	{
		$patients_hash{$_} = 1;
	}
}

# ucsc/HUGO mapping
my %id2sym;
open(M, "/mnt/projects/hdall/results/id-mappings.tsv") or croak "ERROR: could not read id mappings\n";
while(<M>)
{
	chomp;
	my ($sym, $id) = split(/\t/);
	$id2sym{$id} = $sym;
}
close(M);
INFO(scalar(keys(%id2sym))." id mappgins read from file /mnt/projects/hdall/results/id-mappings.tsv");

# refseq/ucsc mapping
my %transcripts;
my %refseq2ucsc;
open(G,"/mnt/projects/generic/data/hg19/hg19.kgXref.txt") or die "ERROR: could not open file /mnt/projects/generic/data/hg19/hg19.kgXref.txt";
while(<G>)
{
	chomp;
	my ($kgID, $mRNA, $spID, $spDisplayID, $geneSymbol, $refSeq, $protAcc, $description, $rfamAcc, $tRnaName) = split(/\t/);

	if ($mRNA =~ /^NM_/)
	{
		$transcripts{$kgID}{'refseq'} = $mRNA;
		$refseq2ucsc{$mRNA} = $kgID;
	}
	elsif ($refSeq =~ /^NM_/)
	{
		$transcripts{$kgID}{'refseq'} = $refSeq;
		$refseq2ucsc{$refSeq} = $kgID if (!$refseq2ucsc{$refSeq});
	}	
}
close(G);

my $lines = 0;
open(G,"/mnt/projects/generic/data/hg19/hg19.knownGene.txt") or die "could not open file /mnt/projects/generic/data/hg19/hg19.knownGene.txt";
while(<G>)
{
	chomp;
	my ($ucsc_id, $chrom, $strand, $txStart, $txEnd, $cdsStart, $cdsEnd,
		$exonCount, $exonStarts, $exonEnds, $proteinID, $alignID) = split(/\t/);

	# compute protein length	
	my @es = split(",", $exonStarts);
	my @ee = split(",", $exonEnds);
	
	if ($cdsStart and $cdsStart < $cdsEnd)
	{
		my ($st, $en, $cdslen);
				
		if ($strand eq '+')
		{
			for (my $i = 0; $i < @es and $cdsEnd > $es[$i]; $i ++)
			{
				next if ($cdsStart > $ee[$i]);
				$st = ($cdsStart > $es[$i] and $cdsStart < $ee[$i]) ? $cdsStart : $es[$i];
				$en = ($cdsEnd > $es[$i] and $cdsEnd < $ee[$i]) ? $cdsEnd : $ee[$i];
				$cdslen += $en-$st;
				$transcripts{$ucsc_id}{'splice_pos'}{$i+1} = int($cdslen / 3);	
			}		
		}
		else
		{
			for (my $i = @es-1; $i >= 0 and $cdsStart < $ee[$i]; $i --)
			{
				next if ($cdsEnd < $es[$i]);
				$st = ($cdsStart > $es[$i] and $cdsStart < $ee[$i]) ? $cdsStart : $es[$i];
				$en = ($cdsEnd > $es[$i] and $cdsEnd < $ee[$i]) ? $cdsEnd : $ee[$i];
				$cdslen += $en-$st;
				$transcripts{$ucsc_id}{'splice_pos'}{@es-$i} = int($cdslen / 3);	
			}
		}
		
		$transcripts{$ucsc_id}{'protlen'} = $cdslen/3;
		#print "protein length NM_002834: ", $transcripts{$ucsc_id}{'protlen'}, "\n" if ($ucsc_id eq "uc001ttx.3");
		$transcripts{$ucsc_id}{'hugo'} = $id2sym{$ucsc_id};
	}
	
	$lines++;
}
close(G);
INFO("$lines genes read from file /mnt/projects/generic/data/hg19/hg19.knownGene.txt");

open(D,"/mnt/projects/hdall/results/lolliplot/pfam-regions.filtered.tsv") or die "could not open file /mnt/projects/hdall/results/lolliplot/pfam-regions.filtered.tsv";
my %domains;
while(<D>)
{
	chomp;
	my ($hugo, $ucsc, $refseq, $uniprot, $domain_id, $pfamname, $start, $end) = split(/\t/);
	
	$domains{"$ucsc:$domain_id"} = defined $domains{"$ucsc:$domain_id"} ? $domains{"$ucsc:$domain_id"} + 1 : 1;
	my $domain_key = "$domain_id:".$domains{"$ucsc:$domain_id"};
	
	$domains{$ucsc}{$domain_key}{id} = $domain_id;
	$domains{$ucsc}{$domain_key}{source} = "Pfam27";
	$domains{$ucsc}{$domain_key}{name} = $pfamname;
	$domains{$ucsc}{$domain_key}{start} = $start;
	$domains{$ucsc}{$domain_key}{end} = $end;
	
	$lines++;
}
close(D);
INFO("$lines domain annotations read from file /mnt/projects/hdall/results/lolliplot/pfam-regions.filtered.tsv");

# read variants
# TABLE: filtered-variants
$lines = 0;
my %variants;
my $skipped_minaf = 0;
open(V, $filtered_variants_file) or die "could not open file $filtered_variants_file\n";
<V>; # skip header
while(<V>)
{
	chomp;
	my ($patient, $sample, $var_type, $status, $rejected_because, $chr, $pos, $dbSNP, $ref, $alt, $gene, $add_genes, $impact, $effect_notused, $non_silent, $deleterious, $exons, 
		$dp_rem_tot, $dp_rem_ref, $dp_rem_var, $freq_rem, $dp_leu_tot, $dp_leu_ref, $dp_leu_var, $freq_leu, $aa_change, $snpeff) = split("\t");

	next if ($patients_list and !$patients_hash{$patient});
	next if ($status eq "REJECT");
	if ($min_af and $freq_leu < $min_af)
	{
		$skipped_minaf ++;
		next;
	}
	
	$snpeff =~ s/EFF=//;
	foreach my $eff (split(",", $snpeff))
	{
		my ($effect, $rest) = $eff =~ /([^\(]+)\(([^\)]+)\)/
			or die "ERROR: could not parse SNP effect: $snpeff\n";

		# skip mutations not affecting coding sequence of protein			
		next if ($effect =~ /^(UPSTREAM|DOWNSTREAM|UTR_5_PRIME|UTR_5_DELETED|START_GAINED|UTR_3_PRIME|UTR_3_DELETED|INTRON|INTRON_CONSERVED|INTERGENIC|INTERGENIC_CONSERVED|INTRAGENIC|EXON)$/);

		my ($impact, $class, $codon_change, $aa_change, $aa_length, $gene_name, $gene_biotype, 
			$coding, $transcript, $exon, $genotype_num) = split('\|', $rest)
				or die "ERROR: could not parse SNP effect: $eff\n";

		$transcript =~ s/\.\d+$//; # remove version number from accession
		$transcript =~ s/\.\d+$//; 

		my $ucsc = $refseq2ucsc{$transcript};
		if (!$ucsc)
		{
			print STDERR "WARNING: Could not map RefSeq ID $transcript to UCSC ID.\n";
			next;
		}
		#print "$transcript -> $ucsc\n";
		
		# map splice site mutations onto protein sequence
		if ($effect eq "SPLICE_SITE_ACCEPTOR")
		{
			$aa_change = $transcripts{$ucsc}{'splice_pos'}{$exon-1};
		}
		elsif ($effect eq "SPLICE_SITE_DONOR")
		{
			$aa_change = $transcripts{$ucsc}{'splice_pos'}{$exon};			
		}
		
		if (!$aa_change)
		{
			print STDERR "WARNING: Could not map following mutation to protein sequence: $transcript $eff. Maybe UTR variant?\n";
			next;
		}
		
		$variants{"dia"}{$ucsc}{"$patient\t$var_type\t$status\t$chr\t$pos\t$aa_change"} = "$effect" if ($sample eq "rem_dia");
		$variants{"rel"}{$ucsc}{"$patient\t$var_type\t$status\t$chr\t$pos\t$aa_change"} = "$effect" if (($patient ne "715" and $sample eq "rem_rel") | ($patient eq "715" and $sample eq "rem_rel2")); # for patient 715 relapse sample is actually third relapse... 
		$variants{"both"}{$ucsc}{"$patient\t$var_type\t$status\t$chr\t$pos\t$aa_change"} = "$effect";		 
	}

	$lines ++;
}
close(V);
INFO("$lines variants read from file $filtered_variants_file");
INFO("$skipped_minaf variants skipped with AF below $min_af") if ($min_af);


Lolliplot->new
(
	hugos => $hugos,
	variants => $variants{"dia"}, 
	transcripts => \%transcripts, 
	domains => \%domains,
	output_directory => $output_directory,
	basename => "lolliplot_",
	suffix => "_dia",
	lolli_shape => "circle"
);

Lolliplot->new
(
	hugos => $hugos,
	variants => $variants{"rel"}, 
	transcripts => \%transcripts, 
	domains => \%domains,
	output_directory => $output_directory,
	basename => "lolliplot_",
	suffix => "_rel",
	lolli_shape => "circle"
);

Lolliplot->new
(
	hugos => $hugos,
	variants => $variants{"both"}, 
	transcripts => \%transcripts, 
	domains => \%domains,
	output_directory => $output_directory,
	basename => "lolliplot_",
	suffix => "_both",
	lolli_shape => "circle"
);