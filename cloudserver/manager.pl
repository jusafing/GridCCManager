#!/usr/bin/perl -w
use Gridcc;
use CloudConfig;
use strict;
package GLOBAL;
	our $fname = "MANAGER";
package main;
##############################################################################
startLog($GLOBAL::fname);
startAws($GLOBAL::fname,$GV::AWS_ACCESS_KEY,$GV::AWS_SECRET_KEY);
##############################################################################
my $arguments = @ARGV;
logMsgT($GLOBAL::fname,"Missing argument",-1,$GV::LOGFILE) if ($arguments != 1);
logMsgT($GLOBAL::fname,"Invalid argument format",-1,$GV::LOGFILE) unless ($ARGV[0] =~ /.+\|[0-9]+/);
my @data = split(/\|/,$ARGV[0]);
if ($data[0] && $data[1])
{
	logMsgT($GLOBAL::fname,"Allocating job: TIME($data[0])-($data[1])",2,$GV::LOGFILE);
	allocateJob($GLOBAL::fname,$GV::EC2,$data[1],"$data[0]");
}
else
{
	print "SYNTAX ERROR. ./manager TIME JOB\n";
	print "Arguments received:\n" if ($data[0] or $data[1]);
	print "\t-> TIME : ($data[1])\n" if ($data[1]);
	print "\t-> JOB  : ($data[0])\n" if ($data[0]);
}
##############################################################################
