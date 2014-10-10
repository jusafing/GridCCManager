#!/usr/bin/perl -w
use DateTime;
use NodeCloud;
use strict;
#############################################################################
my $id 		= rand(1000000);
my $fname	= "SENDER";
my @task_data	= split(/\|/,$ARGV[0]);
my $job 	= $task_data[0];
my $instance_ip = $task_data[1];
my $time_job	= $task_data[2]; 
logMsgT($fname,"No Job specified",-1,$GV::LOGFILE) unless ($job);
logMsgT($fname,"Job received: ($job)",2,$GV::LOGFILE);
#############################################################################
open (FIFO, "+>$GV::FIFO") || die "ERROR, Can't write on ($GV::FIFO): $!\n";
logMsgT($fname,"Sending START signal to daemon: JOB ID ($id|1)",2,$GV::LOGFILE);
my $init_time = time;
print FIFO "$id|1\n";
close(FIFO);
sleep 2;    # to avoid dup signals
#############################################################################
system("cd $job && bash $GV::HOME/$job/commands") && logMsgT($fname,"ERROR-($?)",0,$GV::LOGFILE);
logMsgT($fname,"Creating DONE file ($job/done)",2,$GV::LOGFILE);
open(FILEOK,">$GV::HOME/$job/done") || logMsgT($fname,"DONE file ($job/done) could not be created",0,$GV::LOGFILE);
print FILEOK "done\n";
close(FILEOK);
#############################################################################
open (FIFO_0, "+>$GV::FIFO") || die "ERROR, Can't write on ($GV::FIFO): $!\n";
logMsgT($fname,"Sending STOP  signal to daemon: JOB ID ($id|0)",2,$GV::LOGFILE);
my $final_time = time;
print FIFO_0 "$id|0\n";
close(FIFO_0);
my $total_time = $final_time - $init_time;
my $delta_exp  = $total_time - $time_job;
logMsgT($fname,"Delta time execution process ($instance_ip)|($job)|($id)|($time_job)|($total_time)|($delta_exp)",2,$GV::LOGFILE);
#############################################################################
sleep 2;    # to avoid dup signals
