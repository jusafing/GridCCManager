use strict;
##############################################################################
package GV;
	our $HOME	= "/home/gridcc";
        our $LOGFILE    = "$HOME/node/cloudserver/cloud.log";
        our $TASKFILE   = "$HOME/node/task.log";
        our $FIFO       = "$HOME/node/pool.fifo";
        our $MAXTIME    = 300;
        our $DEBUG      = 1;
package main;
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
	open($logfile_fh,">>$logfile") || print "ERROR, LOGFILE ($logfile) could not be opened\n";
	print $logfile_fh "$msg_data";
	print "$msg_data";
	close($logfile_fh);
	print "$msg_data\n" if ( $msg_code ==-1 );
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
1;
