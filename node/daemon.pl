#!/usr/bin/perl -w
use NodeCloud;
use strict;
use POSIX;
##############################################################################
createProcess("NODE");
##############################################################################
##############################################################################
## Description: Creates new process for FIFO and instance killer            ##
## Author     : Javier Santillan                                            ##
## Syntax     : createProcess($FUNCTION_NAME)			            ##
##############################################################################
sub createProcess
{
        my $function_caller = shift;
        my $function_name   = getFunctionName($function_caller,(caller(0))[3]);
	my $pid             = fork();
	if (not defined $pid)
	{
		logMsgT($function_name,"DEBUG: ERROR. A New process could not be created",-1,$GV::LOGFILE);
	}
	elsif ($pid == 0)
	{
		my $kpid  = getpid();
		my $jobs_counter = 0;
		logMsgT($function_name,"KILLER: Starting killer process (PID $kpid)",2,$GV::LOGFILE);
		for(my $i=0;$i<$GV::MAXTIME;$i++)
		{
			$jobs_counter = 0;
			my $time = $GV::MAXTIME - $i;
			logMsgT($function_name,"KILLER: Time left ($time sec)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			open(FILE,"<$GV::TASKFILE") || logMsgT($function_name,"KILLER: $function_name: Task file could not be readed",0,$GV::LOGFILE);
			while(<FILE>)
			{
				chomp();
				my @task = split(/\|/,$_);
				logMsgT($function_name,"KILLER: Looking for active tasks ($task[0]|$task[1])",3,$GV::LOGFILE) if ($GV::DEBUG == 1);	
				if ($_ =~ /[0-9]+\|[01]/ && $task[1] == 1)
				{
					logMsgT($function_name,"KILLER: Active task found",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
					$jobs_counter++;
				}
			}
			close(FILE);
			logMsgT($function_name,"KILLER: Active task flag ($jobs_counter)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			if ($jobs_counter > 0 )
			{
				logMsgT($function_name,"KILLER: Task in the pool. Holding killer counter",2,$GV::LOGFILE) if ($GV::DEBUG == 1);
				$i = 0;
			}
			sleep 1;
		}
		logMsgT($function_name,"MAXTIME ($GV::MAXTIME) reached. *** This instance is going down now ***",2,$GV::LOGFILE);
		#terminateInstance();
		exit(0);
	}
	else
	{
		logMsgT($function_name,"DAEMON: Starting receiver process",2,$GV::LOGFILE);
		while(1)
		{
			open(FIFOFH, "+< $GV::FIFO") || logMsgT($function_name,"The FIFO file ($GV::FIFO)  could not be readed",-1,$GV::LOGFILE);
			logMsgT($function_name,"DAEMON: Waiting for tasks ...",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			while (<FIFOFH>)
			{
				chomp();
				logMsgT($function_name,"DAEMON: Task Received ($_)",2,$GV::LOGFILE);
				updateTask($function_name,$_);
			}
			close(FIFOFH);
		}
	}
}
##############################################################################
##############################################################################
## Description: Updates file of tasks			                    ##
## Author     : Javier Santillan                                            ##
## Syntax     : updateTask($FUNCTION_NAME,$TASK)                            ##
##############################################################################
sub updateTask
{
        my ($function_caller,$task) = @_;
        my $function_name = getFunctionName($function_caller,(caller(0))[3]);
	my %current_task;
	logMsgT($function_name,"DAEMON: Received to update ($task)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
	unless ($task =~ /[0-9]+\|[01]/)
	{
		logMsgT($function_name,"DAEMON: ERROR, Invalid format. Task refused ($task)",0,$GV::LOGFILE);
		return;
	}
	my @update = split(/\|/,$task);
	open(TASKFILE_FH,"<$GV::TASKFILE") || logMsgT($function_name,"DAEMON: Task file ($GV::TASKFILE) could not be readed",0,$GV::LOGFILE);
	while(<TASKFILE_FH>)
	{
		chomp();
		my @line = split(/\|/,$_);
		$current_task{$line[0]}=$line[1] if ($_ =~ /[0-9]+\|[01]/);
	}
	close(TASKFILE_FH);
	open(TASKFILE_FH,">$GV::TASKFILE") || logMsgT($function_name," DAEMON: Task file ($GV::TASKFILE) could not be written",0,$GV::LOGFILE);
	my $oldvalue = $current_task{$update[0]} if (defined $current_task{$update[0]} && $current_task{$update[0]} =~ m/[01]/);
	$current_task{$update[0]} = $update[1];
	if (defined $current_task{$update[0]} && $current_task{$update[0]} =~ m/[01]/)
	{
		logMsgT($function_name,"DAEMON: Updated task ($update[0]|$oldvalue)->($update[1])",2,$GV::LOGFILE);
	}
	else
	{
		logMsgT($function_name,"DAEMON: Created new task ($update[0]|$update[1])",2,$GV::LOGFILE);
	}
	foreach my $taskid (keys%current_task)
	{
		logMsgT($function_name,"DAEMON: Writing $taskid|$current_task{$taskid}",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
		print TASKFILE_FH "$taskid|$current_task{$taskid}\n";
	}
	close(TASKFILE_FH);
}
