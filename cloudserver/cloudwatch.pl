#!/usr/bin/perl -w
##########################################################################
use DateTime;
use Gridcc;
use CloudConfig;
use strict;
##########################################################################
my $function_name	= "CLOUDWATCH";
my $current_time_epoch	= time;
my $report_time_epoch 	= $current_time_epoch - $GV::NODE_TIMEREPORT;
my $limit		= $GV::NODE_TIMEREPORT/60;
my $report_time_all  	= DateTime->from_epoch( epoch => $report_time_epoch );
my $report_time_hms    	= $report_time_all->hms;
my %data_graph		;
logMsgT($function_name,"CURRENT_EPOCH: ($current_time_epoch) REPORT_EPOCH: ($report_time_epoch) LIMIT ($limit)",2,$GV::LOGFILE);
open(INSFILE_FH,"<$GV::INSFILE") || logMsgT($function_name,"Instance file ($GV::INSFILE) could not be opened",2,$GV::LOGFILE);
while(<INSFILE_FH>)
{
	chomp();
	my @line = split(/\|/,$_);
	getSarData($function_name,$line[1],$GV::NODE_SARFILE,$report_time_hms,$limit) if ($line[1] =~ /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/);
	getSarData($function_name,$line[4],$GV::NODE_SARFILE,$report_time_hms,$limit) if ($line[4] =~ /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/);
}
%data_graph = createDataMatrix($function_name);
foreach my $value (keys%data_graph)
{
	print "**>($value)-($data_graph{$value})\n";
}
createGraphs($function_name,\%data_graph);
