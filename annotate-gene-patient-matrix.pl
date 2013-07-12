use warnings FATAL => qw( all );
use strict;

use lib "$ENV{HOME}/generic/scripts";
use Generic;
use Log::Log4perl qw(:easy);
use Carp;
use Getopt::Long;

# parse detailed results first
my ($gene_patient_matrix, $smg_dia, $smg_rel, $smp_dia_file, $smp_rel_file, $cnv);
GetOptions
(
	"gene-patient-matrix=s" => \$gene_patient_matrix,
	"smg-dia=s" => \$smg_dia,   
	"smg-rel=s" => \$smg_rel,   
	"smp-dia=s" => \$smp_dia_file,  
	"smp-rel=s" => \$smp_rel_file,
	"cnv=s" => \$cnv   
);

# read significantly mutated genes at diagnosis
my %smg_dia_pvalue;
open(D,"$smg_dia") or croak "ERROR: could not read file $smg_dia\n";
<D>; # skip header
while(<D>)
{
	chomp;
	my ($gene, $indels, $snvs, $totmut, $covd_bps, $mut_per_mb, $p_fcpt, $p_lrt, $p_ct, $fdr_fcpt, $fdr_lrt, $fdr_ct) = split(/\t/);
	$smg_dia_pvalue{$gene} = $p_ct;
}
close(D);
INFO(scalar(keys(%smg_dia_pvalue))." genes read from file $smg_dia");

# read significantly mutated genes at relapse
my %smg_rel_pvalue;
open(R,"$smg_rel") or croak "ERROR: could not read file $smg_rel\n";
<R>; # skip header
while(<R>)
{
	chomp;
	my ($gene, $indels, $snvs, $totmut, $covd_bps, $mut_per_mb, $p_fcpt, $p_lrt, $p_ct, $fdr_fcpt, $fdr_lrt, $fdr_ct) = split(/\t/);
	$smg_rel_pvalue{$gene} = $p_ct;
}
close(R);
INFO(scalar(keys(%smg_rel_pvalue))." genes read from file $smg_rel");

# read significantly mutated pathways at diagnosis
my (%smp_dia, %smp_dia_genes);
open(D,"$smp_dia_file") or croak "ERROR: could not read file $smp_dia_file\n";
<D>; # skip header
while(<D>)
{
	chomp;
	my ($id, $name, $class, $samples_affected, $total_variations, $p, $fdr, $num_genes, $genes) = split(/\t/);
	next if ($class ne "BBID" and $class ne "BIOCARTA" and $class ne "KEGG_PATHWAY" and $class ne "OMIM_DISEASE");
	$smp_dia{$id."|".$name} = $p;
	next if ($p > 0.05);
	foreach my $g (split(",", $genes))
	{
		$smp_dia_genes{$g}{'pvalue'} = $p if (!exists $smp_dia_genes{$g}{'pvalue'} or $smp_dia_genes{$g}{'pvalue'} > $p);
		$smp_dia_genes{$g}{$id."|".$name} = $p;
	}
}
close(D);
INFO(scalar(keys(%smp_dia_genes))." pathways read from file $smp_dia_file");

# read significantly mutated pathways at relapse
my (%smp_rel, %smp_rel_genes);
open(D,"$smp_rel_file") or croak "ERROR: could not read file $smp_rel_file\n";
<D>; # skip header
while(<D>)
{
	chomp;
	my ($id, $name, $class, $samples_affected, $total_variations, $p, $fdr, $num_genes, $genes) = split(/\t/);
	next if ($class ne "BBID" and $class ne "BIOCARTA" and $class ne "KEGG_PATHWAY" and $class ne "OMIM_DISEASE");
	$smp_rel{$id."|".$name} = $p;
	next if ($p > 0.05);
	foreach my $g (split(",", $genes))
	{
		$smp_rel_genes{$g}{'pvalue'} = $p if (!exists $smp_rel_genes{$g}{'pvalue'} or $smp_rel_genes{$g}{'pvalue'} > $p);
		$smp_rel_genes{$g}{$id."|".$name} = $p;
	}
}
close(D);
INFO(scalar(keys(%smp_rel_genes))." pathways read from file $smp_rel_file");

# read copy-number info
my (%cnvs);
my $cnv_read = 0;
open(D,"$cnv") or croak "ERROR: could not read CNV file $cnv\n";
<D>; # skip header: patient\tsample\tgene\tchr\tstart\tend\ttrlen\tcdslen\texons\tcosmic\tdescr\tcnumber\tevent\tevent_coordinate\tevent_size\tnum_genes\n
while(<D>)
{
	chomp;
	my ($patient, $sample, $gene, $chr, $start, $end, $trlen, $cdslen, $exons, $cosmic, $descr, $cnumber, $event, $event_coordinate, $event_size, $num_genes) = split(/\t/);
	$cnvs{$patient}{$sample}{$gene}{'cnumber'} = $cnumber;
	$cnvs{$patient}{$sample}{$gene}{'event'} = $event;
	$cnv_read ++;
}
close(D);
INFO("$cnv_read CNVs read from file $cnv");

# TABLE: gene-patient-matrix
open(M,"$gene_patient_matrix") or croak "ERROR: could not read file $gene_patient_matrix\n";
my (%gene_info, @patients_dia, @patients_rel, @patients_cons);
my $header = <M>;
chomp($header);
my @hfields = split("\t", $header);
for (my $d = 17; $d <= 36; $d ++) { push(@patients_dia, $hfields[$d]); }
for (my $d = 45; $d <= 64; $d ++) { push(@patients_rel, $hfields[$d]); }
for (my $d = 67; $d <= 86; $d ++) { push(@patients_cons, $hfields[$d]); }

while(<M>)
{
	chomp;
	my @fields = split /\t/;

	my $g = $fields[0];

	$gene_info{$g}{'desc'} = $fields[1];
	$gene_info{$g}{'chr'} = $fields[2];
	$gene_info{$g}{'start'} = $fields[3];
	$gene_info{$g}{'end'} = $fields[4];
	$gene_info{$g}{'exons'} = $fields[5];
	$gene_info{$g}{'tr_len'} = $fields[6];
	$gene_info{$g}{'cds_len'} = $fields[7];
	$gene_info{$g}{'cosmic'} = $fields[8];
		
	$gene_info{$g}{'freq-dia'} = $fields[9];
	$gene_info{$g}{'tot-dia'} = $fields[10];
	$gene_info{$g}{'freq-dia-ns'} = $fields[11];
	$gene_info{$g}{'tot-dia-ns'} = $fields[12];
	$gene_info{$g}{'max-af-dia'} = $fields[13];
	$gene_info{$g}{'max-af-dia-ns'} = $fields[14];
	$gene_info{$g}{'imp-ex-dia'} = $fields[15];
	$gene_info{$g}{'imp-ex-dia-ns'} = $fields[16];
	for (my $d = 17; $d <= 36; $d ++) { $gene_info{$g}{$patients_dia[$d-17]} = $fields[$d]; }

	$gene_info{$g}{'freq-rel'} = $fields[37];
	$gene_info{$g}{'tot-rel'} = $fields[38];
	$gene_info{$g}{'freq-rel-ns'} = $fields[39];
	$gene_info{$g}{'tot-rel-ns'} = $fields[40];
	$gene_info{$g}{'max-af-rel'} = $fields[41];
	$gene_info{$g}{'max-af-rel-ns'} = $fields[42];
	$gene_info{$g}{'imp-ex-rel'} = $fields[43];
	$gene_info{$g}{'imp-ex-rel-ns'} = $fields[44];
	for (my $d = 45; $d <= 64; $d ++) { $gene_info{$g}{$patients_rel[$d-45]} = $fields[$d]; }

	$gene_info{$g}{'freq-cons'} = $fields[65];
	$gene_info{$g}{'tot-cons'} = $fields[66];
	for (my $d = 67; $d <= 86; $d ++) { $gene_info{$g}{$patients_cons[$d-67]} = $fields[$d]; }
}
close(M);
INFO(scalar(keys(%gene_info))." genes read from file $gene_patient_matrix");

# output header
print "gene\tdescr\tchr\tstart\tend\texons\ttr_len\tcds_len\tcosmic\t";
print "freq-dia\ttot-dia\tfreq-dia-ns\ttot-dia-ns\tmax-af-dia\tmax-af-dia-ns\timp-ex-dia\timp-ex-dia-ns\tp-gene-dia\tp-pw-dia";
map { print "\t$_" } (@patients_dia);
print "\tfreq-rel\ttot-rel\tfreq-rel-ns\ttot-rel-ns\tmax-af-rel\tmax-af-rel-ns\timp-ex-rel\timp-ex-rel-ns\tp-gene-rel\tp-pw-rel";
map { print "\t$_" } (@patients_rel);
print "\tfreq-cons\ttot-cons";
map { print "\t$_" } (@patients_cons);
print "\tenr-pw-dia\tenr-pw-rel\tenr-pw-rel-spec";
print "\n";

foreach my $g (keys(%gene_info))
{
	print "$g";
	print "\t",$gene_info{$g}{'desc'},"\t",$gene_info{$g}{'chr'},"\t",$gene_info{$g}{'start'},"\t",$gene_info{$g}{'end'},"\t",$gene_info{$g}{'exons'},"\t",$gene_info{$g}{'tr_len'},"\t",$gene_info{$g}{'cds_len'},"\t",$gene_info{$g}{'cosmic'};

	print "\t".(defined $gene_info{$g}{'freq-dia'} ? $gene_info{$g}{'freq-dia'} : "");
	print "\t".(defined $gene_info{$g}{'tot-dia'} ? $gene_info{$g}{'tot-dia'} : "");
	print "\t".(defined $gene_info{$g}{'freq-dia-ns'} ? $gene_info{$g}{'freq-dia-ns'} : "");
	print "\t".(defined $gene_info{$g}{'tot-dia-ns'} ? $gene_info{$g}{'tot-dia-ns'} : "");
	print "\t".(defined $gene_info{$g}{'max-af-dia'} ? $gene_info{$g}{'max-af-dia'} : "");
	print "\t".(defined $gene_info{$g}{'max-af-dia-ns'} ? $gene_info{$g}{'max-af-dia-ns'} : "");
	print "\t".(defined $gene_info{$g}{'imp-ex-dia'} ? $gene_info{$g}{'imp-ex-dia'} : "");
	print "\t".(defined $gene_info{$g}{'imp-ex-dia-ns'} ? $gene_info{$g}{'imp-ex-dia-ns'} : "");

	print "\t".(defined $smg_dia_pvalue{$g} ? $smg_dia_pvalue{$g} : ""); 
	print "\t".(defined $smp_dia_genes{$g}{'pvalue'} ? $smp_dia_genes{$g}{'pvalue'} : "");
	foreach my $pdia (@patients_dia)
	{
		print "\t";
		next if (!$gene_info{$g}{$pdia} or $gene_info{$g}{$pdia} eq " ");
		print $gene_info{$g}{$pdia};
		
		my ($p) = $pdia =~ /(.*?)-dia/; 
		if ($cnvs{$p}{'rem_dia'}{$g})
		{
			print "|".$cnvs{$p}{'rem_dia'}{$g}{'event'}.":".$cnvs{$p}{'rem_dia'}{$g}{'cnumber'};
		}		
	} 

	print "\t".(defined $gene_info{$g}{'freq-rel'} ? $gene_info{$g}{'freq-rel'} : "");
	print "\t".(defined $gene_info{$g}{'tot-rel'} ? $gene_info{$g}{'tot-rel'} : "");
	print "\t".(defined $gene_info{$g}{'freq-rel-ns'} ? $gene_info{$g}{'freq-rel-ns'} : "");
	print "\t".(defined $gene_info{$g}{'tot-rel-ns'} ? $gene_info{$g}{'tot-rel-ns'} : "");
	print "\t".(defined $gene_info{$g}{'max-af-rel'} ? $gene_info{$g}{'max-af-rel'} : "");
	print "\t".(defined $gene_info{$g}{'max-af-rel-ns'} ? $gene_info{$g}{'max-af-rel-ns'} : "");
	print "\t".(defined $gene_info{$g}{'imp-ex-rel'} ? $gene_info{$g}{'imp-ex-rel'} : "");
	print "\t".(defined $gene_info{$g}{'imp-ex-rel-ns'} ? $gene_info{$g}{'imp-ex-rel-ns'} : "");

	print "\t".(defined $smg_rel_pvalue{$g} ? $smg_rel_pvalue{$g} : ""); 
	print "\t".(defined $smp_rel_genes{$g}{'pvalue'} ? $smp_rel_genes{$g}{'pvalue'} : ""); 

	foreach my $prel (@patients_rel)
	{
		print "\t";
		next if (!$gene_info{$g}{$prel} or $gene_info{$g}{$prel} eq " ");
		print $gene_info{$g}{$prel};
		
		my ($p) = $prel =~ /(.*?)-rel/; 
		if ($cnvs{$p}{'rem_rel'}{$g})
		{
			print "|".$cnvs{$p}{'rem_rel'}{$g}{'event'}.":".$cnvs{$p}{'rem_rel'}{$g}{'cnumber'};
		}		
	} 

	print "\t".(defined $gene_info{$g}{'freq-cons'} ? $gene_info{$g}{'freq-cons'} : "");
	print "\t".(defined $gene_info{$g}{'tot-cons'} ? $gene_info{$g}{'tot-cons'} : "");
	map { print "\t".(defined $gene_info{$g}{$_} ? $gene_info{$g}{$_} : "") } (@patients_cons);

	print "\t";
	my @enriched_pw_dia;
	map { push(@enriched_pw_dia, $_."(".sprintf("%.1e", $smp_dia_genes{$g}{$_}).")") if ($_ ne 'pvalue') } sort {$smp_dia_genes{$g}{$a} <=> $smp_dia_genes{$g}{$b}} keys(%{$smp_dia_genes{$g}});
	print join(",", @enriched_pw_dia);

	print "\t";
	my @enriched_pw_rel;
	map { push(@enriched_pw_rel, $_."(".sprintf("%.1e", $smp_rel_genes{$g}{$_}).")") if ($_ ne 'pvalue') } sort {$smp_rel_genes{$g}{$a} <=> $smp_rel_genes{$g}{$b}} keys(%{$smp_rel_genes{$g}});
	print join(",", @enriched_pw_rel);

	print "\t";
	my @enriched_pw_rel_spec;
	map { push(@enriched_pw_rel_spec, $_."(".sprintf("%.1e", $smp_rel{$_}).")") if ($_ ne 'pvalue' and $smp_rel{$_} < 0.01 and (!defined $smp_dia{$_} or $smp_dia{$_} > 0.1)) } sort {$smp_rel_genes{$g}{$a} <=> $smp_rel_genes{$g}{$b}} keys(%{$smp_rel_genes{$g}});
	print join(",", @enriched_pw_rel_spec);
	 
	print "\n";
}