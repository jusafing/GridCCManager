package GV;
	our $WEBDIR	     = "/www/monitoring";
	our $MONDIR	     = "/home/gridcc/cloudserver/mon_data";
        our $LOGFILE         = "/home/gridcc/cloudserver/cloud.log";
        our $INSFILE         = "/home/gridcc/cloudserver/instance.log";
	our $SERVERHOME	     = "/home/gridcc";
        our $AWS_ACCESS_KEY  = "";
        our $AWS_SECRET_KEY  = "";
	our $AWS_AMI	     = "ami-e0fd7989";
	our $AWS_ITYPE	     = "t1.micro";
	our $AWS_KERNELID    = "aki-407d9529";
	our $AWS_SECGRP	     = "default";
	our $AWS_KEYNAME     = "CLIENTS";
	our $NODE_HOME       = "/home/gridcc/";
	our $NODE_SARFILE    = "$NODE_HOME/node/mon.sar";
	our $NODE_SENDER     = "$NODE_HOME/node/sender.pl";
	our $NODE_SSHPORT    = 2200;
	our $NODE_SSHUSER    = "gridcc";
	our $NODE_TIMEREPORT = 1800;
	our $NODE_TIMEOUT    = 30;
	our $NODE_TRIES      = 50;
        our $MAX_TIME        = 3420;
	our $REDUNDANCY	     = 0;
        our $DEBUG           = 1;
        our $EC2             ;
        our $LFH             ;
1;