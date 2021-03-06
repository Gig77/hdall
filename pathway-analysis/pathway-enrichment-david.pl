#!perl
use strict;
use warnings FATAL => qw( all );

use SOAP::Lite;
use HTTP::Cookies;
use Data::Dumper;
use Carp;

# read id mapping
#my (%name2ensembl, %symbol2desc);
#open(GENES, "/mnt/projects/hdall/results/gene-symbols-to-ensembl-geneid.txt") or die "ERROR: could not read gene list\n";
#<GENES>;
#while(<GENES>)
#{
#	chomp;
#	my ($gene_name, $ensemblid, $species, $desc) = split("\t");
#	$name2ensembl{$gene_name} = $ensemblid;
#}
#close(GENES);

# read biomart id mapping
my %name2id;
open(GENES, "/mnt/projects/generic/data/ensembl/gene-id-mapping.biomart-0.7.tsv") or die "ERROR: could not read gene list\n";
<GENES>;
while(<GENES>)
{
	chomp;
	my ($approved_symbol, $entrez_gene_id, $accession_numbers, $approved_name, 
		$previous_symbols, $previous_names, $aliases, $name_aliases, $entrez_gene_id_ncbi) = split("\t");

	$entrez_gene_id = $entrez_gene_id_ncbi if (!$entrez_gene_id);
	next if (!$entrez_gene_id);

	$name2id{$approved_symbol} = $entrez_gene_id;
	map {$name2id{$_} = $entrez_gene_id} split(", ", $previous_symbols);
	$name2id{$entrez_gene_id} = $approved_symbol;		
}
close(GENES);

# map additional identifiers not yet in biomart list
#$name2id{FLJ14186} = 401149;
#$name2id{MGC70870} = 403340;
#$name2id{LOC100288637} = 100288637;
#$name2id{LOC389834} = 389834;
#$name2id{LOC220729} = 220729;
#$name2id{FLJ37453} = 729614;
#$name2id{LOC285696} = 285696;
#$name2id{LOC729732} = 729732;
#$name2id{LOC100507412} = 100507412;
#$name2id{LOC100129858} = 100129858;
#$name2id{FLJ46361} = 375940;
#$name2id{LOC653786} = 653786;
#$name2id{LOC100129931} = 100129931;
#$name2id{LOC96610} = 96610;
#$name2id{LOC619207} = 619207;
#$name2id{FLJ45340} = 402483;
#$name2id{LOC150622} = 150622;
#$name2id{LOC100131320} = 100131320;
#$name2id{'HGC6.3'} = 100128124;
#$name2id{FLJ12825} = 440101;
#$name2id{LOC728323} = 728323;
#$name2id{LOC728407} = 728407;
#$name2id{LOC644669} = 644669;
#$name2id{PEAK1} = 79834;
#$name2id{LOC115110} = 115110;
#$name2id{MGC39584} = 441058;
#$name2id{LOC442132} = 442132;
#$name2id{LOC100131047} = 100131047;
#$name2id{LOC100233156} = 100233156;
#$name2id{LOC643837} = 643837;
#$name2id{LOC100134229} = 100134229;
#$name2id{LOC283788} = 283788;
#$name2id{LOC646626} = 646626;
#$name2id{FLJ43681} = 388574;
#$name2id{LOC284661} = 284661;
#$name2id{LOC389332} = 389332;
#$name2id{MGC45800} = 90768;
#$name2id{LOC1720} = 1720;
#$name2id{FLJ42709} = 441094;
#$name2id{FLJ39739} = 388685;
#$name2id{LOC256880} = 256880;
#$name2id{UG0898H09} = 643763;
#$name2id{LOC340508} = 340508;
#$name2id{LOC392232} = 392232;
#$name2id{LOC407835} = 407835;
#$name2id{LOC100286793} = 100286793;
#$name2id{'HEATR8-TTC4'} = 100527960;
#$name2id{LOC146880} = 146880;
#$name2id{LOC646214} = 646214;
#$name2id{LOC388692} = 388692;
#$name2id{LOC100190940} = 100190940;
#$name2id{MGC2752} = 65996;
#$name2id{LOC100129726} = 100129726;
#$name2id{LOC643406} = 643406;
#$name2id{LOC100126784} = 100126784;
#$name2id{LOC100506071} = 100506071;
#$name2id{LOC285441} = 285441;
#$name2id{LOC728819} = 728819;
#$name2id{LOC100128573} = 100128573;
#$name2id{'SENP3-EIF4A1'} = 100533955;
#$name2id{LOC654433} = 654433;
#$name2id{LOC100128164} = 100128164;
#$name2id{LOC100216545} = 100216545;
#$name2id{LOC100131825} = 100131825;
#$name2id{LOC100506710} = 100506710;
#$name2id{LOC401010} = 401010;
#$name2id{LOC645513} = 645513;
#$name2id{LOC284100} = 284100;

# read input genes from stdin and map to entrez gene ids
my (@genes, @entrez_genes);
while(<>)
{
	chomp;
	my $id = $name2id{$_};
	if (!$id)
	{
		print STDERR "WARNING: Input gene name $_ could not be mapped to a Entrez Gene ID. This gene will be excluded from analysis.\n";
		next;
	}
	push(@genes, $_);
	push(@entrez_genes, $id);
}

die "ERROR: could not read input gene names from STDIN\n"
	if (@genes == 0);
	
print STDERR "The following genes will be tested for enrichment:\n";
print STDERR join(",", @genes)."\n";

my $soap = SOAP::Lite                             
	-> uri('http://service.session.sample')                
	-> proxy('http://david.abcc.ncifcrf.gov/webservice/services/DAVIDWebService',
			cookie_jar => HTTP::Cookies->new(ignore_discard=>1));

 #user authentication by email address
 #For new user registration, go to http://david.abcc.ncifcrf.gov/webservice/register.htm
 my $check = $soap->authenticate('christian.frech@ccri.at')->result;
  	print STDERR "User authentication: $check\n";

 if (lc($check) eq "true") { 


  #list conversion types
 # AFFYMETRIX_3PRIME_IVT_ID,AFFYMETRIX_EXON_GENE_ID,AFFYMETRIX_SNP_ID,AGILENT_CHIP_ID,AGILENT_ID,AGILENT_OLIGO_ID,ENSEMBL_GENE_ID,ENSEMBL_TRANSCRIPT_ID,
 # ENTREZ_GENE_ID,FLYBASE_GENE_ID,FLYBASE_TRANSCRIPT_ID,GENBANK_ACCESSION,GENOMIC_GI_ACCESSION,GENPEPT_ACCESSION,ILLUMINA_ID,IPI_ID,MGI_ID,PFAM_ID,PIR_ID,
 # PROTEIN_GI_ACCESSION,REFSEQ_GENOMIC,REFSEQ_MRNA,REFSEQ_PROTEIN,REFSEQ_RNA,RGD_ID,SGD_ID,TAIR_ID,UCSC_GENE_ID,UNIGENE,UNIPROT_ACCESSION,UNIPROT_ID,
 # UNIREF100_ID,WORMBASE_GENE_ID,WORMPEP_ID,ZFIN_ID
 #my $conversionTypes = $soap ->getConversionTypes()->result;
#	 print STDERR "\nConversion Types: \n$conversionTypes\n"; 
	 
 #list all annotation category names
 # BBID,BIND,BIOCARTA,BLOCKS,CGAP_EST_QUARTILE,CGAP_SAGE_QUARTILE,CHROMOSOME,COG_NAME,COG_ONTOLOGY,CYTOBAND,DIP,EC_NUMBER,ENSEMBL_GENE_ID,ENTREZ_GENE_ID,
 # ENTREZ_GENE_SUMMARY,GENETIC_ASSOCIATION_DB_DISEASE,GENERIF_SUMMARY,GNF_U133A_QUARTILE,GENETIC_ASSOCIATION_DB_DISEASE_CLASS,GOTERM_BP_2,GOTERM_BP_1,
 # GOTERM_BP_4,GOTERM_BP_3,GOTERM_BP_FAT,GOTERM_BP_5,GOTERM_CC_1,GOTERM_BP_ALL,GOTERM_CC_3,GOTERM_CC_2,GOTERM_CC_5,GOTERM_CC_4,GOTERM_MF_1,GOTERM_MF_2,
 # GOTERM_CC_FAT,GOTERM_CC_ALL,GOTERM_MF_5,GOTERM_MF_FAT,GOTERM_MF_3,GOTERM_MF_4,HIV_INTERACTION_CATEGORY,HIV_INTERACTION_PUBMED_ID,GOTERM_MF_ALL,
 # HIV_INTERACTION,KEGG_PATHWAY,HOMOLOGOUS_GENE,INTERPRO,OFFICIAL_GENE_SYMBOL,NCICB_CAPATHWAY_INTERACTION,MINT,PANTHER_MF_ALL,PANTHER_FAMILY,
 # PANTHER_BP_ALL,OMIM_DISEASE,PFAM,PANTHER_SUBFAMILY,PANTHER_PATHWAY,PIR_SUPERFAMILY,PIR_SUMMARY,PIR_SEQ_FEATURE,PROSITE,PUBMED_ID,REACTOME_INTERACTION,
 # REACTOME_PATHWAY,PIR_TISSUE_SPECIFICITY,PRINTS,PRODOM,PROFILE,SMART,SP_COMMENT,SP_COMMENT_TYPE,SP_PIR_KEYWORDS,SCOP_CLASS,SCOP_FAMILY,
 # SCOP_FOLD,SCOP_SUPERFAMILY,UP_SEQ_FEATURE,UNIGENE_EST_QUARTILE,ZFIN_ANATOMY,UP_TISSUE,TIGRFAMS,SSF,UCSC_TFBS
 my $allCategoryNames= $soap ->getAllAnnotationCategoryNames()->result;	 	  	
 print STDERR  "\nAll available annotation category names: \n$allCategoryNames\n";
 
 my $default_categories = "KEGG_PATHWAY,OMIM_DISEASE,COG_ONTOLOGY,SP_PIR_KEYWORDS,UP_SEQ_FEATURE,GOTERM_BP_FAT,GOTERM_CC_FAT,GOTERM_MF_FAT,BBID,BIOCARTA,INTERPRO,PIR_SUPERFAMILY,SMART";
 my $additional_categories = "UP_SEQ_FEATURE";
 $soap->setCategories("$default_categories,$additional_categories")
 	or croak "ERROR: could not set categories\n";
# print "$validated_categories[0]\n";
# exit;
 
 #addList
 #my $inputIds = 'KRAS,WSCD1,KRT17,MLL3,CREBBP,MGC70870,PDE4DIP,DEGS2,MST1L,DNAH9,XG,HOXB9,ZNF492,PDHA1';
 my $inputIds = join(",", @entrez_genes);
 my $idType = 'ENTREZ_GENE_ID';
 my $listName = 'cancer';
 my $listType=0;
 #to add background list, set listType=1
 my $list = $soap->addList($inputIds, $idType, $listName, $listType)->result;
 print STDERR "Percentage of mapped genes: $list\n"; 
 
 #list all species  names
 my $allSpecies= $soap ->getSpecies()->result;	 	  	
 # print STDERR  "\nAll species: \n$allSpecies\n"; 
 #list current species  names
 my $currentSpecies= $soap->getCurrentSpecies()->result;	 	  	
 print STDERR  "Current species: $currentSpecies\n"; 

 #set user defined species 
 #my $species = $soap ->setCurrentSpecies("1")->result;

 #print STDERR "\nCurrent species: \n$species\n"; 
 
#set user defined categories 
#my $categories = $soap ->setCategories("BBID,BIOCARTA,COG_ONTOLOGY,INTERPRO,KEGG_PATHWAY,OMIM_DISEASE,PIR_SUPERFAMILY,SMART,UP_SEQ_FEATURE")->result;
#to user DAVID default categories, send empty string to setCategories():
 my $categories = $soap ->setCategories("")->result;
print STDERR "Valid categories: $categories\n";  
 
print "Category\tTerm\tCount\t%\tPvalue\tGenes\tList Total\tPop Hits\tPop Total\tFold Enrichment\tBonferroni\tBenjamini\tFDR\n";
#close chartReport;

#open (chartReport, ">>", "chartReport.txt");
#getChartReport 	
my $thd=0.1;
my $ct = 2;
my $chartReport = $soap->getChartReport($thd,$ct);
	my @chartRecords = $chartReport->paramsout;
	#shift(@chartRecords,($chartReport->result));
	#print $chartReport->result."\n";
  	print STDERR "Total chart records: ".(@chartRecords+1)."\n";
  	print STDERR "\n ";
	#my $retval = %{$chartReport->result};
	my @chartRecordKeys = keys %{$chartReport->result};
	
	#print "@chartRecordKeys\n";
	
	my @chartRecordValues = values %{$chartReport->result};
		
	for my $j (0 .. (@chartRecords-1))
	{			
		my %chartRecord = %{$chartRecords[$j]};
		my $categoryName = $chartRecord{"categoryName"};
		my $termName = $chartRecord{"termName"};
		my $listHits = $chartRecord{"listHits"};
		my $percent = $chartRecord{"percent"};
		my $ease = $chartRecord{"ease"};
		my $Genes = $chartRecord{"geneIds"};
		my @gene_symbols;
		map { push(@gene_symbols, $name2id{$_} ? $name2id{$_} : $_) } (split(", ", $Genes)); # back translate entrez gene id to gene symbol
		my $listTotals = $chartRecord{"listTotals"};
		my $popHits = $chartRecord{"popHits"};
		my $popTotals = $chartRecord{"popTotals"};
		my $foldEnrichment = $chartRecord{"foldEnrichment"};
		my $bonferroni = $chartRecord{"bonferroni"};
		my $benjamini = $chartRecord{"benjamini"};
		my $FDR = $chartRecord{"afdr"};
					
		print "$categoryName\t$termName\t$listHits\t$percent\t$ease\t",join(",", @gene_symbols),"\t$listTotals\t$popHits\t$popTotals\t$foldEnrichment\t$bonferroni\t$benjamini\t$FDR\n";				 
	}		  	
	
	print STDERR "Done.\n";
} 
__END__
		
