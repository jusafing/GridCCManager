use Net::Amazon::EC2;
use VM::EC2;
use GD::Graph::area;
use CloudConfig;
use POSIX;
use strict;
##############################################################################
sub startLog
{
	my $function_caller 	= shift;
	my $function_name 	= getFunctionName($function_caller,(caller(0))[3]);
	logMsgT($function_name,"**************************",2,$GV::LOGFILE);
	logMsgT($function_name,"***  STARTING MANAGER  ***",2,$GV::LOGFILE);
	logMsgT($function_name,"**************************",2,$GV::LOGFILE);
}
##############################################################################
##############################################################################
## Description: Creates a new EC2 object in order to connect to AWS	    ##
## Author     : Javier Santillan					    ##
## Syntax     : startAws(FUNCTION_NAME,EC2_OBJ)		  	   	    ##
##############################################################################
sub startAws
{
        my ($function_caller,$aws_ak,$aws_sk) = @_;
        my $function_name = getFunctionName($function_caller,(caller(0))[3]);
	logMsgT($function_name,"Connecting to AWS using ($aws_ak)-($aws_sk)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
	$GV::EC2  = VM::EC2->new(-access_key => $aws_ak, -secret_key => $aws_sk);
}
##############################################################################
##############################################################################
## Description: Creates new instance. Returns its ID and private ip addresss##
## Author     : Javier Santillan					    ##
## Syntax     : newInstance(FUNCTION_NAME,EC2_OBJ)		  	    ##
##############################################################################
sub newInstance
{
	my ($function_caller,$ec2) = @_;
        my $function_name 	 = getFunctionName($function_caller,(caller(0))[3]);
	my $initial_instime	 = time;
        my @instance 		 = $ec2->run_instances(
				-image_id       => $GV::AWS_AMI, 
				-min_count      => 1, 
				-max_count      => 1, 
				-key_name       => $GV::AWS_KEYNAME, 
				-security_group => $GV::AWS_SECGRP, 
				-instance_type  => $GV::AWS_ITYPE, 
				-kernel_id      => $GV::AWS_KERNELID);
	my $status 		 = $ec2->wait_for_instances(@instance);
	my @failed 		 = grep {$status->{$_} ne 'running'} @instance;
 	logMsgT($function_name,"Unable to retrieve instance status: @failed",1,$GV::LOGFILE);
	my $instance_id  	 = $ec2->instance_parm(@instance);
	my $new_instance	 = $ec2->describe_instances(-instance_id=>$instance_id);
	my $instance_private_ip  = $new_instance->privateIpAddress;
	logMsgT($function_name,"Created new instance ($instance_id)-($instance_private_ip)",2,$GV::LOGFILE);
	my $final_instime	= time;
	my $delta_instime	= $final_instime - $initial_instime;
	logMsgT($function_name,"Delta time for instance creation process:($instance_id)|($instance_private_ip)|($delta_instime)",2,$GV::LOGFILE);
	return "$instance_id|$instance_private_ip";
}
##############################################################################
##############################################################################
## Description: Terminates a existing instance			   	    ##
## Author     : Javier Santillan					    ##
## Syntax     : terminateInstance(FUNCTION_NAME,EC2_OBJ,INSTANCE_ID)  	    ##
##############################################################################
sub terminateInstance
{
        my ($function_caller,$ec2,$instance_id) = @_;
        my $function_name = getFunctionName($function_caller,(caller(0))[3]);
	logMsgT($function_name,"Terminating instance ($instance_id)",2,$GV::LOGFILE);
	my @result = $ec2->terminate_instances(-instance_id => $instance_id);
	my $status = $ec2->wait_for_instances(@result);
	
}
##############################################################################
##############################################################################
## Description: Schedules a new job acording to the available instances	    ##
## Author     : Javier Santillan					    ##
## Syntax     : allocateJob(FUNCTION_NAME,EC2_OBJ,TIME_JOB,JOB_TO_EXECUTE)  ##
##############################################################################
sub allocateJob
{
        my ($function_caller,$ec2,$time_job,$process_job) = @_;
        my $function_name     	= getFunctionName($function_caller,(caller(0))[3]);
	my $allocate_flag	= 0;
	my $new_instance_flag	= 0;
	my $allocated_data	;
	my $allocated_flag 	= 0;
	open(IFH,"<$GV::INSFILE") || logMsgT($function_name,"Instances file ($GV::INSFILE) could not be opened",-1,$GV::LOGFILE);
	logMsgT($function_name,"Allocating job (Time: $time_job)",2,$GV::LOGFILE) if ($GV::DEBUG == 1);
	while (<IFH>)
	{
		next if $_ =~ m/^$/;
		chomp();
		my $instance_data = $_;
		my @field 	  = split(/\|/,$instance_data);
		my @gast 	  = split(/\./,$field[2]);
		if ( $time_job <= $gast[1])
		{
			$allocated_flag = allocateOnInstance($function_name,$field[1],$process_job,$new_instance_flag,$time_job);
			if ($GV::REDUNDANCY == 1)
			{
				if ($field[4] eq "NULL")
				{
					logMsgT($function_name,"Reduncancy is activated, but there is no backup instance for ($field[0])",1,$GV::LOGFILE);
					logMsgT($function_name,"Skipping allocating job on backup instance",1,$GV::LOGFILE);
				}
				else
				{
					$allocated_flag = allocateOnInstance($function_name,$field[4],$process_job,$new_instance_flag,$time_job);
				}
			}
			$allocate_flag  = 1;
			$allocated_data = "$field[0]|$field[1]|$time_job|NULL|NULL";
			$allocated_data = "$field[0]|$field[1]|$time_job|$field[3]|$field[4]" if ($GV::REDUNDANCY == 1);
			last;
		}
	}
	close(IFH);
	if ($allocate_flag == 0)
	{
		my $new_instance 	= newInstance($function_name,$ec2);
		my $new_instance_back 	= newInstance($function_name,$ec2) if ($GV::REDUNDANCY == 1);
		my @field 	 	= split(/\|/,$new_instance);
		$new_instance_flag 	= 1;
		$allocated_flag = allocateOnInstance($function_name,$field[1],$process_job,$new_instance_flag,$time_job);
		$allocated_flag = allocateOnInstance($function_name,$field[4],$process_job,$new_instance_flag,$time_job) if ($GV::REDUNDANCY == 1);
		$allocated_data 	= "$new_instance|$time_job|NULL|NULL";
		$allocated_data 	= "$new_instance|$time_job|$new_instance_back" if ($GV::REDUNDANCY == 1);
	}
	updateInstanceList($function_name,$allocated_data,$new_instance_flag) if ($allocated_flag == 1);
	return $new_instance_flag;
}
##############################################################################
##############################################################################
## Description: Updates the file of available instances.		    ##
## Author     : Javier Santillan					    ##
## Syntax     : updateInstanceList(FUNCTION_NAME,ALLOCATED_DATA,NEW_INSTANCE_FLAG)##
##############################################################################
sub updateInstanceList
{
        my ($function_caller,$allocated_data,$new_instance_flag) = @_;
        my $function_name = getFunctionName($function_caller,(caller(0))[3]);
	my @data = split(/\|/,$allocated_data);
	my $new_hasp;
	my $updated = 0;
	logMsgT($function_name,"Allocated data ($data[0]|$data[1]|$data[2]) New instance flag ($new_instance_flag) Redundancy: ($GV::REDUNDANCY)",2,$GV::LOGFILE);
	open(OIFH,"<$GV::INSFILE") || logMsgT($function_name,"Instances file ($GV::INSFILE) could not be opened",0,$GV::LOGFILE);
	open(NIFH,">$GV::INSFILE.tmp") || logMsgT($function_name,"Instances file ($GV::INSFILE.tmp) could not be opened",0,$GV::LOGFILE);
	if ($new_instance_flag == 1)
	{
		logMsgT($function_name,"New Instance flag activated",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
		if ($data[2] > $GV::MAX_TIME)
		{
			logMsgT($function_name,"Job time ($data[2]) greater than ($GV::MAX_TIME)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			my $ent   = (int $data[2] / $GV::MAX_TIME) + 1;
			my $res   = $data[2] % $GV::MAX_TIME;
			$new_hasp = "$ent.$res";
		}
		else
		{
			logMsgT($function_name,"Job time ($data[2]) smaller than ($GV::MAX_TIME)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			my $asp  = $GV::MAX_TIME - $data[2];
			$new_hasp = "1.$asp";
			logMsgT($function_name,"Calculating: $GV::MAX_TIME ASP: $data[2] ASP: $asp NEW hasp: $new_hasp",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
		}
		while(<OIFH>)
		{
			next if $_ =~ m/^$/;
			chomp();
			my @field 	= split(/\|/,$_);
			my $line	= $_;
			logMsgT($function_name,"EVAL ($new_hasp)-($field[2])",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
	 		if($new_hasp < $field[2] && $updated == 0 )
			{
				if ($GV::REDUNDANCY == 1) {print NIFH "$data[0]|$data[1]|$new_hasp|$data[3]|$data[4]\n";}
				else {print NIFH "$data[0]|$data[1]|$new_hasp|NULL|NULL\n";}
				$updated = 1;
			}
			print NIFH "$line\n";
		}
		if ($GV::REDUNDANCY == 1)
		{
			print NIFH "$data[0]|$data[1]|$new_hasp|$data[3]|$data[4]\n" if ($updated == 0);
			logMsgT($function_name,"Updated list values (new instance added)-($data[0]|$data[1]|$new_hasp|$data[3]|$data[4])",2,$GV::LOGFILE);
		}
		else
		{
			print NIFH "$data[0]|$data[1]|$new_hasp|NULL|NULL\n" if ($updated == 0);
			logMsgT($function_name,"Updated list values (new instance added)-($data[0]|$data[1]|$new_hasp|NULL|NULL)",2,$GV::LOGFILE);
		}
	}
	else
	{
		while(<OIFH>)
		{
			next if $_ =~ m/^$/;
			chomp();
			my @field 	= split(/\|/,$_);
			my @asp  	= split(/\./,$field[2]);
			my $line	= $_;
	 		if($data[1] eq $field[1] && $updated == 0)
			{
				my $nasp  = $asp[1] - $data[2];
				$new_hasp = "$asp[0].$nasp"; 
				$line = "$field[0]|$field[1]|$new_hasp|$field[3]|$field[4]";
				logMsgT($function_name,"MATCH $line",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
				$updated = 1;
				logMsgT($function_name,"Updated list values (Update ASP)-($data[0]|$data[1]|$field[2] -> $new_hasp)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			}
			print NIFH "$line\n";
		}
	}
	close(OIFH);	
	close(NIFH);	
	rename "$GV::INSFILE.tmp",$GV::INSFILE;
}
##############################################################################
##############################################################################
## Description: Allocates a job into a new instance.			    ##
## Author     : Javier Santillan					    ##
## Syntax     : allocateOnInstance($FNAME,$INSTANCE_IP,$JOB,$NEW_INSTANCE)  ##
##############################################################################
sub allocateOnInstance
{
        my ($function_caller,$instance_ip,$job,$new_instance,$time_job) = @_;
        my $function_name = getFunctionName($function_caller,(caller(0))[3]);
	my $initial_run;
	my $final_run;
	if ($new_instance == 1)
	{
                logMsgT($function_name,"New instance was created for new job. Waiting response from ($instance_ip)",2,$GV::LOGFILE);
		my $response 	= 0;
		my $count	= 1;
		$initial_run = time;
		while($response != 1 && $count < $GV::NODE_TRIES)
		{
			system("ssh -p $GV::NODE_SSHPORT $GV::NODE_SSHUSER\@$instance_ip -oStrictHostKeyChecking=no -C \"uptime\"") or $response = 1;
			logMsgT($function_name,"Response from instance Attempt($count)-($instance_ip)-($!)",2,$GV::LOGFILE);
			sleep 1;
			$count++;
		}
		$final_run = time;
		if ($count == $GV::NODE_TRIES)
		{
			logMsgT($function_name,"Connection error, intance ($instance_ip) could not be reached.",0,$GV::LOGFILE);
			return 0;
		}
	}
	sleep 10;
	my $initial_scptime  = time;
	logMsgT($function_name,"Executing (scp -P $GV::NODE_SSHPORT -oStrictHostKeyChecking=no -r $GV::SERVERHOME/$job $GV::NODE_SSHUSER\@$instance_ip:$GV::NODE_HOME/$job)",2,$GV::LOGFILE);
	system("scp -P $GV::NODE_SSHPORT -oStrictHostKeyChecking=no -r $GV::SERVERHOME/$job $GV::NODE_SSHUSER\@$instance_ip:$GV::NODE_HOME/$job") 
	&& logMsgT($function_name,"Error during the SCP process ($!)",0,$GV::LOGFILE);
	my $final_scptime = time;
	logMsgT($function_name,"Creating a new process for execution of (ssh -p $GV::NODE_SSHPORT $GV::NODE_SSHUSER\@$instance_ip -oStrictHostKeyChecking=no -C \"$GV::NODE_SENDER \\\"$job|$instance_ip|$time_job\\\"\")",2,$GV::LOGFILE);
	my $sshpid = fork();
	if (not defined $sshpid)
	{
		logMsgT($function_name,"New process for SSH execution could not be created",0,$GV::LOGFILE);
		return 0;
	}
	elsif ($sshpid == 0)
	{
		my $ssh_cpid  = getpid();
		logMsgT($function_name,"SSH execution process for job ($job) PID:($ssh_cpid)",2,$GV::LOGFILE);
		system("ssh -p $GV::NODE_SSHPORT $GV::NODE_SSHUSER\@$instance_ip -oStrictHostKeyChecking=no -C \"$GV::NODE_SENDER \\\"$job|$instance_ip|$time_job\\\"\"")
		&& logMsgT($function_name,"Error during the SSH Execute command process ($!)",0,$GV::LOGFILE);
		exit(0);
	}
	else
	{
		my $delta_scp = $final_scptime - $initial_scptime;
		my $delta_run = $final_run     - $initial_run;
		logMsgT($function_name,"Delta time for allocation process:($instance_ip)|($job)|RUN($delta_run)|SCP($delta_scp)",2,$GV::LOGFILE);
		return 1;
	}
}
##############################################################################
##############################################################################
## Description: Creates a new Amazon instance using Net::Amazon::EC2	    ##
## Author     : Javier Santillan					    ##
## Syntax     : newInstanceA(FUNCTION_NAME,EC2 OBJECT)	 		    ##
##############################################################################
sub newInstanceA
{
	my ($function_caller,$ec2) = @_;
        my $function_name 	 = getFunctionName($function_caller,(caller(0))[3]);
        my $instance 		 = $ec2->run_instances(ImageId => 'ami-cc66dfa5', MinCount => 1, MaxCount => 1, KeyName => 'CLIENTS', SecurityGroup => 'default', InstanceType => 't1.micro', KernelId => 'aki-407d9529');
	my $instance_id 	 = $instance->instances_set->[0]->instance_id;
	logMsgT($function_name,"Created new instance ($instance_id)",2,$GV::LOGFILE);
	my $new_ip 		 = $ec2->allocate_address();
	if ($new_ip)
	{
		logMsgT($function_name,"New IP address allocated ($new_ip)",2,$GV::LOGFILE);
	}
	else
	{
		logMsgT($function_name,"New IP addres allocated error ($new_ip)",0,$GV::LOGFILE);
	}
	sleep(30);
	my $associate = $ec2->associate_address(PublicIp => $new_ip, InstanceId => $instance_id);
	if ($associate)
	{
		logMsgT($function_name,"Associate IP [$new_ip]-[$instance_id] succesful",2,$GV::LOGFILE);
	}
	else
	{
		logMsgT($function_name,"Associate IP [$new_ip]-[$instance_id] error",0,$GV::LOGFILE);
	}
}
##############################################################################
##############################################################################
## Description: Creates a matrix data from sources data files.		    ##
## Author     : Javier Santillan					    ##
## Syntax     : createDataMatrix(FUNCTION_CALLER)			    ##
##############################################################################
sub createDataMatrix
{
	my $function_caller = shift;
        my $function_name   = getFunctionName($function_caller,(caller(0))[3]);
	my %timestamp       ;
	my @averages	    ;
	my @instances	    ;
	my $count	    = 0;
	my $flag_avg	    = 0;
	$averages[$count++] = "INSTANCE [IP_ADDR]";
	$averages[$count++] = "UPTIME";
	$averages[$count++] = "CPU USAGE  [%]";
	$averages[$count++] = "MEM USAGE  [Kb]";
	$averages[$count++] = "NET INPUT  [Kb/s]";
	$averages[$count++] = "NET OUTPUT [Kb/s]";
	$averages[$count++] = "DISK USAGE [%]";
	open(FILE,"<$GV::INSFILE") || logMsgT($function_name,"The data file ($GV::INSFILE) could not be opened",0,$GV::LOGFILE);
	while(<FILE>)
	{
		chomp();
		my @line = split(/\|/,$_);
		push(@instances,$line[1]);
		push(@instances,$line[4]) if ($line[4] ne "NULL");
	}
	close(FILE);
	foreach my $instance (@instances)
	{
		logMsgT($function_name,"AVG instance-($count)-($instance)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
		$averages[$count++] = $instance;
		open(FILE,"<$GV::MONDIR/monitor_upt_$instance.tmp") || logMsgT($function_name,"The data file ($GV::MONDIR/monitor_upt_$instance.tmp) could not be opened",0,$GV::LOGFILE);
		while(<FILE>)
		{
			chomp();
			if ($_ =~ /.+up.+,/)
			{
				my @line = split(",",$_);
				$line[0] =~ s/.+up(.+)/$1/;
				logMsgT($function_name,"AVG uptime-($count)-($line[0])",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
				$averages[$count++] = "$line[0]";
				$flag_avg = 1;
			}
		}
		close(FILE);
		if ($flag_avg == 0 )
		{
			logMsgT($function_name,"No value received for AVG upt. Fixing to 0.00",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			$averages[$count++] = "0.00";
			logMsgT($function_name,"AVG upt-($count)-(0.00)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
		}
		$flag_avg = 0;
		open(FILE,"<$GV::MONDIR/monitor_cpu_$instance.tmp") || logMsgT($function_name,"The data file ($GV::MONDIR/monitor_cpu_$instance.tmp) could not be opened",0,$GV::LOGFILE);
		while(<FILE>)
		{
			chomp();
			if ($_ =~ /^Average/)
			{
				my @line = split(" ",$_);
				my $cpu_usage = $line[2]*1 + $line[6]*1;
				logMsgT($function_name,"AVG cpu-($count)-($cpu_usage)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
				$averages[$count++] = "$cpu_usage";
				$flag_avg = 1;
				next;
			}
			next unless $_ =~ /^..:..:../;
			my @line = split(" ",$_);
			next unless ($line[2] =~ /[0-9]+/);
			next unless ($line[6] =~ /[0-9]+/);
			$line[0] =~ s/(..:..):../$1/;
			my $cpu_usage = $line[2]*1 + $line[6]*1;
			$timestamp{"$instance-$line[0]"} .= "|$cpu_usage";				
		}
		close(FILE);
		if ($flag_avg == 0 )
		{
			logMsgT($function_name,"No value received for AVG cpu. Fixing to 0.00",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			$averages[$count++] = "0.00";
			logMsgT($function_name,"AVG cpu-($count)-(0.00)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
		}
		$flag_avg = 0;
		open(FILE,"<$GV::MONDIR/monitor_mem_$instance.tmp") || logMsgT($function_name,"The data file ($GV::MONDIR/monitor_mem_$instance.tmp) could not be opened",0,$GV::LOGFILE);
		while(<FILE>)
		{
			chomp();
			if ($_ =~ /^Average/)
			{
				my @line = split(" ",$_);
				logMsgT($function_name,"AVG mem-($count)-($line[2])",3,$GV::LOGFILE) if($GV::DEBUG == 1);
				$averages[$count++] = "$line[2]";
				$flag_avg = 1;
				next;
			}
			next unless $_ =~ /^..:..:../;
			my @line = split(" ",$_);
			next unless $line[2] =~ /[0-9]+/;
			$line[0] =~ s/(..:..):../$1/;
			$timestamp{"$instance-$line[0]"} .= "|$line[2]";				
		}
		close(FILE);
		if ($flag_avg == 0 )
		{
			logMsgT($function_name,"No value received for AVG mem. Fixing to 0.00",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			$averages[$count++] = "0.00";
			logMsgT($function_name,"AVG mem-($count)-(0.00)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
		}
		$flag_avg = 0;
		open(FILE,"<$GV::MONDIR/monitor_net_$instance.tmp") || logMsgT($function_name,"The data file ($GV::MONDIR/monitor_net_$instance.tmp) could not be opened",0,$GV::LOGFILE);
		while(<FILE>)
		{
			chomp();
			if ($_ =~ /^Average/)
			{
				my @line = split(" ",$_);
				logMsgT($function_name,"AVG neti-($count)-($line[4])",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
				$averages[$count++] = "$line[4]";
				logMsgT($function_name,"AVG neto-($count)-($line[5])",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
				$averages[$count++] = "$line[5]";
				$flag_avg = 1;
				next;
			}
			next unless $_ =~ /^..:..:../;
			my @line = split(" ",$_);
			$line[0] =~ s/(..:..):../$1/;
			next unless $line[4] =~ /[0-9]+/;
			$timestamp{"$instance-$line[0]"} .= "|$line[4]|$line[5]";				
		}
		close(FILE);
		if ($flag_avg == 0 )
		{
			logMsgT($function_name,"No value received for AVG neti. Fixing to 0.00",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			$averages[$count++] = "0.00";
			logMsgT($function_name,"AVG neti-($count)-(0.00)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			logMsgT($function_name,"No value received for AVG neto. Fixing to 0.00",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			$averages[$count++] = "0.00";
			logMsgT($function_name,"AVG neto-($count)-(0.00)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
		}
		$flag_avg = 0;
		open(FILE,"<$GV::MONDIR/monitor_hds_$instance.tmp") || logMsgT($function_name,"The data file ($GV::MONDIR/monitor_hds_$instance.tmp) could not be opened",0,$GV::LOGFILE);
		while(<FILE>)
		{
			chomp();
			if ($_ =~ /dev/)
			{
				my @line = split(" ",$_);
				logMsgT($function_name,"AVG hds-($count)-($line[4])",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
				$averages[$count++] = "$line[4]";
				$flag_avg = 1;
			}
		}
		close(FILE);
		if ($flag_avg == 0 )
		{
			logMsgT($function_name,"No value received for AVG hds. Fixing to 0.00",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			$averages[$count++] = "0.00";
			logMsgT($function_name,"AVG hds-($count)-(0.00)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
		}
		$flag_avg = 0;
	}
	my @imgs = ("cpu_graph.gif","mem_graph.gif","neti_graph.gif","neto_graph.gif");
	createSingleTable($function_name,\@averages,\@imgs,7,2,"USE OF RESOURCES BY INSTANCE [Average]","$GV::WEBDIR/summary.html");
	return %timestamp;
}
##############################################################################
##############################################################################
## Description: Creates a HTML table with img from an array of strings      ##
## Author     : Javier Santillan					    ##
## Syntax     : createTableHtml($FNAME,@DATA,$#COLS,$HEADER,$IMG,$OUTPUTFILE)##
##############################################################################
sub createTableHtml
{
	my ($function_caller,$data,$ncols,$header,$img_file,$output_file) = @_;
        my $function_name  = getFunctionName($function_caller,(caller(0))[3]);
	my $html;
	my $total     = @$data;
	my $spanvalue = $total/$ncols;
	$html  = "<html>\n";
	$html .= "<meta http-equiv=\"refresh\" content=\"120\">\n";
	$html .= "<body bgcolor=#111111 text=#ffffff>";
	$html .= "<table align=\"center\" border=2>\n";
	$html .= "<tr><td bgcolor=#111111 text=#aaaaaa align=\"center\" colspan=$spanvalue><b>$header</b></td></tr>";
	$html .= "<tr><td align=\"center\" colspan=$spanvalue><a href=\"$img_file\"><img width=\"600\" height=\"300\"src=\"$img_file\"></td></tr>";
	while($total > 0)
	{
		$html .= "<tr>";
		for(my $j=0; $j < $ncols && $total > 0; $j++)
		{
			my $cell = shift(@$data);
			$total   = @$data;
			logMsgT($function_name,"Items left [$total] Shifting cell ($cell)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			$html .= "<td>$cell</td>";
		}
		$html .= "</tr>\n";
	}
	$html .= "</table>\n";
	$html .= "</html>\n";
	logMsgT($function_name,"Creating file ($output_file)",2,$GV::LOGFILE);
	open(FILE,">$output_file") || logMsgT($function_name,"The data file ($output_file) could not be created",0,$GV::LOGFILE);
	print FILE $html;
	close(FILE);
}
##############################################################################
##############################################################################
## Description: Creates a HTML table from an array of strings 		    ##
## Author     : Javier Santillan					    ##
## Syntax     : createSummTable($FNAME,\@DATA,\@IMGLST,$INDEX,$#COLS,$HEADER,OUTFILE)##
##############################################################################
sub createSingleTable
{
	my ($function_caller,$data,$imglist,$ncols,$index,$header,$output_file) = @_;
        my $function_name  = getFunctionName($function_caller,(caller(0))[3]);
	my $total 	= @$data;
	my $count 	= 0;
	my $html      	;
	$html  = "<html>\n";
	$html .= "<meta http-equiv=\"refresh\" content=\"120\">\n";
	$html .= "<body bgcolor=#111111 text=#ffffff>";
	$html .= "<table align=\"center\" border=2>\n";
	$html .= "<tr><td align=\"center\" colspan=$ncols><h1>$header</h1</td></tr>";
	logMsgT($function_name,"TOTAL elements on array: [$total] INDEX ($index)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
	while($total > 0)
	{
		$html .= "<tr>";
		if ($count == 1)
		{
			for(my $j=0; $j < $ncols; $j++)
			{
				my $item = @$imglist;
				if ($item > 0  && $j >= $index)
				{
					my $img = shift(@$imglist);
					logMsgT($function_name,"Loop imglist ($j) Items left ($item) Cols ($ncols) Adding <td> for ($img)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
					$html .= "<td><a href=\"$img\"><img width=\"200\" height=\"150\" src=\"$img\"></a></td>";
				}
				else
				{
					logMsgT($function_name,"Loop imglist ($j) Items left ($item) Cols ($ncols) Adding empty <td>",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
					$html .= "<td></td>";
				}
			}
		}
		else
		{
			for(my $j=0; $j < $ncols; $j++)
			{
				my $cell = shift(@$data);
				$total = @$data;
				logMsgT($function_name,"CreateSingleTable: Items left [$total] Shifting cell ($cell)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
				$html .= "<td>$cell</td>";
			}
		}
		$html .= "</tr>\n";
		$count++;
	}
	$html .= "</table>\n";
	$html .= "</html>\n";
	logMsgT($function_name,"Creating file ($output_file)",2,$GV::LOGFILE);
	open(FILE,">$output_file") || logMsgT($function_name,"The data file ($output_file) could not be created",0,$GV::LOGFILE);
	print FILE $html;
	close(FILE);
}
##############################################################################
##############################################################################
## Description: Creates a history graph from data file.			    ##
## Author     : Javier Santillan					    ##
## Syntax     : createGraphs(FUNCTION_NAME,HASH_DATA_GRAPH)	 	    ##
##############################################################################
sub createGraphs
{
	my ($function_caller,$data_graph) = @_;
        my $function_name  = getFunctionName($function_caller,(caller(0))[3]);
	my %instances	;
	my @instances_l	;
	my $matrix_value;
	my @times	;
	my @dat		;
	my %cpu		;
	my %mem		;
	my %neti	;
	my %neto	;
	my %cpu_tab	;
	my %mem_tab	;
	my %neti_tab	;
	my %neto_tab	;
	my @cpu_graph	;
	my @mem_graph	;
	my @neti_graph	;
	my @neto_graph	;
	my @cpu_table	;
	my @mem_table	;
	my @neti_table	;
	my @neto_table	;
	my $dat_flag    = 1;
	my $count 	= 0;
	my $aux		= 0;
	
	foreach my $value (sort keys%$data_graph)
	{
		my @line = split("-",$value);
		$times[$count++]=$line[1];
		$instances{$line[0]}++;
	}
	@instances_l = keys%instances;
	my $ninstances = @instances_l;
	$ninstances++;
	push(@cpu_table,"TIME");
	push(@mem_table,"TIME");
	push(@neti_table,"TIME");
	push(@neto_table,"TIME");
	push(@cpu_table,@instances_l);
	push(@mem_table,@instances_l);
	push(@neti_table,@instances_l);
	push(@neto_table,@instances_l);
	logMsgT($function_name,"Pushing [TIME] and [@instances_l] on *_table array",3,$GV::LOGFILE) if ($GV::DEBUG == 1);;
	foreach my $value (sort {$instances{$a} cmp $instances{$b}} keys%instances)
	{
		$matrix_value = $instances{$value};
		last;
	}
	for(my $i=0;$i<$matrix_value;$i++)
	{
		push(@dat,$times[$i]);
	}
	foreach my $value (sort keys%$data_graph)
	{
		my @line = split("-",$value);
		$instances{$line[0]}=1;
	}
	push(@cpu_graph,\@dat);
	push(@mem_graph,\@dat);
	push(@neti_graph,\@dat);
	push(@neto_graph,\@dat);
	$count = @instances_l;
	foreach my $value (sort keys%$data_graph)
#	foreach my $value (sort {$data_graph->{$b} cmp $data_graph->{$a}} keys%$data_graph)
	{
		my @infovalue = split("-",$value);
		my @infodata  = split(/\|/,$data_graph->{$value});
		## Filling the anonymous arrays @{instance} . It could also work with hash of arrays ##
		if ($instances{$infovalue[0]} <= $matrix_value && $aux < $count)
		{
			push(@{$cpu{$infovalue[0]}},$infodata[1]);
			$cpu_tab{$infovalue[1]} .= "$infodata[1]|";
			logMsgT($function_name,"Pushing item on cpu $instances{$infovalue[0]}-($infovalue[0]) $infovalue[1] - $infodata[1]",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			push(@{$mem{$infovalue[0]}},$infodata[2]);  			
			$mem_tab{$infovalue[1]} .= "$infodata[2]|";
			logMsgT($function_name,"Pushing item on mem $instances{$infovalue[0]}-($infovalue[0]) $infovalue[1] - $infodata[2]",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			push(@{$neti{$infovalue[0]}},$infodata[3]);  			
			$neti_tab{$infovalue[1]} .= "$infodata[3]|";
			logMsgT($function_name,"Pushing item on neti $instances{$infovalue[0]}-($infovalue[0]) $infovalue[1] - $infodata[3]",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			push(@{$neto{$infovalue[0]}},$infodata[4]);  			
			$neto_tab{$infovalue[1]} .= "$infodata[4]|";
			logMsgT($function_name,"Pushing item on neto $instances{$infovalue[0]}-($infovalue[0]) $infovalue[1] - $infodata[4]",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			$instances{$infovalue[0]}++;
		}
		if ($instances{$infovalue[0]} > $matrix_value)
		{
			logMsgT($function_name,"Reached MATRIX_VALUE ($instances{$infovalue[0]}) AUX ($aux)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			push(@cpu_graph,\@{$cpu{$infovalue[0]}});
			push(@mem_graph,\@{$mem{$infovalue[0]}});
			push(@neti_graph,\@{$neti{$infovalue[0]}});
			push(@neto_graph,\@{$neto{$infovalue[0]}});
			$instances{$infovalue[0]} = 1;
			$aux++;
		}
	}
	fillArrayTab($function_name,\@cpu_table,\%cpu_tab,$count,"cpu");
	fillArrayTab($function_name,\@mem_table,\%mem_tab,$count,"mem");
	fillArrayTab($function_name,\@neti_table,\%neti_tab,$count,"neti");
	fillArrayTab($function_name,\@neto_table,\%neto_tab,$count,"neto");
	createTableHtml($function_name,\@cpu_table,$ninstances,"HISTORY OF CPU USAGE [%]","cpu_graph.gif","$GV::WEBDIR/cpu_data.html");
	createTableHtml($function_name,\@mem_table,$ninstances,"HISTORY OF MEMORY USAGE [Kb]","mem_graph.gif","$GV::WEBDIR/mem_data.html");
	createTableHtml($function_name,\@neti_table,$ninstances,"HISTORY OF NETWORK ACTIVITY [INPUT Kb/s]","neti_graph.gif","$GV::WEBDIR/neti_data.html");
	createTableHtml($function_name,\@neto_table,$ninstances,"HISTORY OF NETWORK ACTIVITY [OUTPUT Kb/s]","neto_graph.gif","$GV::WEBDIR/neto_data.html");
	createGraphFile($function_name,\@cpu_graph,\@instances_l,"$GV::WEBDIR/cpu_graph","cpu");
	createGraphFile($function_name,\@mem_graph,\@instances_l,"$GV::WEBDIR/mem_graph","mem");
	createGraphFile($function_name,\@neti_graph,\@instances_l,"$GV::WEBDIR/neti_graph","neti");
	createGraphFile($function_name,\@neto_graph,\@instances_l,"$GV::WEBDIR/neto_graph","neto");
}
##############################################################################
##############################################################################
## Description: Creates a graph binary file from a hash of data		    ##
## Author     : Javier Santillan					    ##
## Syntax     : fillArrayTab($FUNCTION_NAME,\@DATA,\%DATA,$FILE,$TYPE)      ##
## Options    : TYPE: cpu, mem, neti, neto				    ##
##############################################################################
sub fillArrayTab
{
	my ($function_caller,$array_data,$hash_data,$total_fields,$type) = @_;
        my $function_name  = getFunctionName($function_caller,(caller(0))[3]);
	foreach my $value (sort keys%$hash_data)
	{
		my @values = split(/\|/,$hash_data->{$value});
		my $nfield = @values;
		push(@$array_data,$value);
		logMsgT($function_name,"Number of fields ($type) hash_value ($value)-($nfield)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
		foreach my $val (@values)
		{
			logMsgT($function_name,"($val)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
			push(@$array_data,$val);
		}
		if ($nfield < $total_fields)
		{
			my $dif = $total_fields - $nfield;
			logMsgT($function_name,"Fixing order of array of ($type) ($value)-($nfield) Should be ($total_fields). Adding ($dif) 'ceros' value",1,$GV::LOGFILE);
			for(my $i=0; $i < $dif; $i++)
			{
				logMsgT($function_name,"pushed (0.0)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
				push(@$array_data,"0.00");
			}
		}
	}
}
##############################################################################
##############################################################################
## Description: Creates a graph binary file from a hash of data		    ##
## Author     : Javier Santillan					    ##
## Syntax     : createGraphFile($FUNCTION_NAME,\@DATA,\@LEGEND,$FILE,$TYPE) ##
## Options    : TYPE: cpu, mem, neti, neto				    ##
##############################################################################
sub createGraphFile
{
	my ($function_caller,$data_graph,$legend,$file,$type) = @_;
        my $function_name  = getFunctionName($function_caller,(caller(0))[3]);
	my $graph = GD::Graph::area->new(1200, 800);
	my $ylabel;
	my $title;
	if ($type eq "cpu")
	{
		$title  = "RUNNING INSTANCES - CPU USAGE";
		$ylabel = "% CPU Usage" 
	}
	elsif ($type eq "mem")
	{
		$title  = "RUNNING INSTANCES - MEMORY USAGE";
		$ylabel = "KB Used" 
	}
	elsif ($type eq "neti")
	{
		$title  = "RUNNING INSTANCES - INPUT - NETWORK ACTIVITY";
		$ylabel = "KB/s Input" 
	}
	elsif ($type eq "neto")
	{
		$title  = "RUNNING INSTANCES - OUTPUT - NETWORK ACTIVITY";
		$ylabel = "Kb/s Output" 
	}
	$graph->set_legend(@$legend);
	$graph->set(
	   'title'            => $title,
	   'x_label'          => "Time",
	   'y_label'          => $ylabel,
	   'long_ticks'       => 1,
	   'tick_length'      => 0,
	   'x_ticks'          => 0,
	   'x_label_position' => .5,
	   'y_label_position' => .5,
	   'cumulate'         => 2,
	   'bgclr'            => 'white',
	   'transparent'      => 0,
	   'y_tick_number'    => 5,
	   'y_number_format'  => '%d',
	   'y_plot_values'    => 1,
	   'x_plot_values'    => 1,
	   'x_labels_vertical'=> 1,
	   'zero_axis'        => 1,
	   'lg_cols'          => 7,
	   'accent_treshold'  => 100_000,
	);
	$graph->plot($data_graph);
	saveChart($function_name,$graph,$file);
}
##############################################################################
##############################################################################
## Description: Creates a nes binary image file	          		    ##
## Author     : Javier Santillan					    ##
## Syntax     : SaveChart(FUNCTION_NAME,CHART,FILE)	  	    	    ##
##############################################################################
sub saveChart
{
	my ($function_caller,$chart,$file) = @_;
        my $function_name  = getFunctionName($function_caller,(caller(0))[3]);
        local(*OUT);
        my $ext = $chart->export_format;
	logMsgT($function_name,"Creating image file ($file.$ext)",2,$GV::LOGFILE);
        open(OUT, ">$file.$ext") || logMsgT($function_name,"Cannot open $file.$ext for write: $!",0,$GV::LOGFILE);
        binmode OUT;
        print OUT $chart->gd->$ext();
        close OUT;
}
##############################################################################
##############################################################################
## Description: Log message function with tracking support		    ##
## Author     : Javier Santillan					    ##
## Syntax     : logMsgT(FUNCTION_NAME,MESSAGE,CODE,LOG_FILE)	  	    ##
## Options    : CODE  >  -1>FATAL_ERROR 0>ERROR  1>WARNING  2>INFO  3>DEBUG ##
##############################################################################
sub logMsgT
{
	my ($function_name, $msg_data, $msg_code,$logfile) = @_;
	my $msg_prefix;
	my $logfile_fh;
	if    ( $msg_code ==-1 ){$msg_prefix = "FATAL ERROR";	}
	elsif ( $msg_code == 0 ){$msg_prefix = "ERROR";		}
	elsif ( $msg_code == 1 ){$msg_prefix = "WARNING";	}
	elsif ( $msg_code == 2 ){$msg_prefix = "INFO";		}
	elsif ( $msg_code == 3 ){$msg_prefix = "DEBUG";		}
	else			{$msg_prefix = "UNDEFINED";	}
        (my $sec,my $min,my $hour,my $day,my $mon,my $year,
	 my $wday,my $yday,my $isdst)=localtime(time);
        my $gdate = sprintf("%4d-%02d-%02dT%02d:%02d:%02d",
		    $year+1900,$mon+1,$day-1,$hour,$min,$sec);
        my $Ddate = sprintf("%4d%02d%02d",$year+1900,$mon+1,$day);
        my $Hdate = sprintf("%02d%02d",$hour,$min);
	my $msg_timestamp = getTimestamp("localtime","Tdate");
	$msg_data = sprintf("[%-.20s]-[%-.11s]-[%.50s]-->[%s]\n",
		$msg_timestamp,$msg_prefix,$function_name,$msg_data);
	open($logfile_fh,">>$logfile") || die "[$msg_timestamp]-[$msg_prefix]-[$function_name]****>ERROR, LOGFILE ($logfile) could not be opened\n";
	print $logfile_fh "$msg_data";
	print "$msg_data";
	close($logfile_fh);
	die "$msg_data\n" if ( $msg_code ==-1 );
}
##############################################################################
##############################################################################
## Description: Returns function_caller + function_name	for tracking        ##
## Author     : Javier Santillan					    ##
## Syntax     : getFunctionName(CURRENT_FUNCTION_CALLER,FUNCTION_NAME)	    ##
##############################################################################
sub getFunctionName
{
        my ($current_function_caller,$function_name) = @_;
        my @names = split(/::/,$function_name);
        return "$current_function_caller|$names[1]";
}
##############################################################################
##############################################################################
## Description: Gets the timestamp of current time			    ##
## Author     : Javier Santillan					    ##
## Syntax     : getTimestamp(TIME_ZONE,TYPE_REQUEST)	 		    ##
## Options    : TIME_ZONE    >  localtime, utc				    ##
## Options    : TYPE_REQUEST >  TDate, Ddate, Hdate			    ##
##############################################################################
sub getTimestamp
{
	my ($time_zone, $time_request) = @_;
	my ($sec, $min, $hour, $day, $mon, $year, $wday, $yday, $isdst);
	if ( $time_zone eq "localtime" )
	{
		($sec, $min, $hour, $day, $mon, $year,
		 $wday, $yday, $isdst)=localtime(time);
	}
	elsif ($time_zone eq "utc")
	{
		($sec, $min, $hour, $day, $mon, $year,
		 $wday, $yday, $isdst)=gmtime(time);
	}
	else
	{
		($sec, $min, $hour, $day, $mon, $year, 
		 $wday, $yday, $isdst)=localtime(time);
	}
        my $Tdate = sprintf("%4d-%02d-%02dT%02d:%02d:%02d",
		    $year+1900,$mon+1,$day-1,$hour,$min,$sec);
        my $Ddate = sprintf("%4d%02d%02d",$year+1900,$mon+1,$day);
        my $Hdate = sprintf("%02d%02d",$hour,$min);
	return $Tdate if ($time_request eq "Tdate");
	return $Ddate if ($time_request eq "Ddate");
	return $Hdate if ($time_request eq "Hdate");
}
##############################################################################
##############################################################################
## Description: Get data from SAR data files on runnind nodes               ##
## Author     : Javier Santillan                                            ##
## Syntax     : getSarData($FUNCTION_NAME,$IP_ADDR,$SAR_FILE,$RTIME,$LIMIT) ##
##############################################################################
sub getSarData
{
        my ($function_caller,$ip,$sar_file,$report_time,$limit) = @_;
        my $function_name = getFunctionName($function_caller,(caller(0))[3]);
        logMsgT($function_name,"Connecting to ($ip) to process SAR file ($sar_file) since ($report_time)",2,$GV::LOGFILE);
        my $cmd_cpu="ssh -p $GV::NODE_SSHPORT $GV::NODE_SSHUSER\@$ip -oStrictHostKeyChecking=no -C \"LC_TIME='POSIX' sar -f $GV::NODE_SARFILE -s $report_time -u | tail -$limit\" > $GV::MONDIR/monitor_cpu_$ip.tmp";
        my $cmd_mem="ssh -p $GV::NODE_SSHPORT $GV::NODE_SSHUSER\@$ip -oStrictHostKeyChecking=no -C \"LC_TIME='POSIX' sar -f $GV::NODE_SARFILE -s $report_time -r | tail -$limit\" > $GV::MONDIR/monitor_mem_$ip.tmp";
        my $cmd_net="ssh -p $GV::NODE_SSHPORT $GV::NODE_SSHUSER\@$ip -oStrictHostKeyChecking=no -C \"LC_TIME='POSIX' sar -f $GV::NODE_SARFILE -s $report_time -n DEV|grep eth0|tail -$limit\">$GV::MONDIR/monitor_net_$ip.tmp";
        my $cmd_hds="ssh -p $GV::NODE_SSHPORT $GV::NODE_SSHUSER\@$ip -oStrictHostKeyChecking=no -C \"df -h | grep xvda | tail -$limit\" > $GV::MONDIR/monitor_hds_$ip.tmp";
        my $cmd_upt="ssh -p $GV::NODE_SSHPORT $GV::NODE_SSHUSER\@$ip -oStrictHostKeyChecking=no -C \"uptime | awk '{print \$3}'| tail -$limit\" > $GV::MONDIR/monitor_upt_$ip.tmp";
	logMsgT($function_name,"--> Retrieving CPU data from($ip)-($cmd_cpu)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
	logMsgT($function_name,"--> Retrieving MEM data from($ip)-($cmd_mem)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
	logMsgT($function_name,"--> Retrieving NET data from($ip)-($cmd_net)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
	logMsgT($function_name,"--> Retrieving HDS data from($ip)-($cmd_hds)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
	logMsgT($function_name,"--> Retrieving UPT data from($ip)-($cmd_upt)",3,$GV::LOGFILE) if ($GV::DEBUG == 1);
	system($cmd_cpu) && logMsgT($function_name,"Could not retrieve CPU data from ($ip)",0,$GV::LOGFILE);
	system($cmd_mem) && logMsgT($function_name,"Could not retrieve MEM data from ($ip)",0,$GV::LOGFILE);
	system($cmd_net) && logMsgT($function_name,"Could not retrieve NET data from ($ip)",0,$GV::LOGFILE);
	system($cmd_hds) && logMsgT($function_name,"Could not retrieve HDS data from ($ip)",0,$GV::LOGFILE);
	system($cmd_upt) && logMsgT($function_name,"Could not retrieve UPT data from ($ip)",0,$GV::LOGFILE);
}
1;
