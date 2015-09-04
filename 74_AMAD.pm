################################################################
# 
# Developed with Kate
#
#  (c) 2015 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
################################################################




package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

use HttpUtils;

my $version = "0.5.9";



sub AMAD_Initialize($) {

    my ($hash) = @_;

    $hash->{SetFn}	= "AMAD_Set";
    $hash->{DefFn}	= "AMAD_Define";
    $hash->{UndefFn}	= "AMAD_Undef";
    $hash->{AttrFn}	= "AMAD_Attr";
    $hash->{ReadFn}	= "AMAD_Read";
    $hash->{AttrList} 	= "setOpenApp ".
			  "setFullscreen:0,1 ".
			  "setScreenOrientation:0,1 ".
			  "setScreenBrightness:0,1 ".
			  "fhemServerIP ".
			  "root:0,1 ".
			  "interval ".
			  "port ".
			  "disable:1 ";
    $hash->{AttrList}	.= $readingFnAttributes;
    
    
    foreach my $d(sort keys %defs) {
	next if($defs{$d}{TYPE} ne "AMAD");
	$defs{$d}->{VERSION} 	= $version;
    }
}

sub AMAD_Define($$) {

my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    return "too few parameters: define <name> AMAD <HOST>" if ( @a != 3 );


    my $name    	= $a[0];
    my $host    	= $a[2];
    my $port		= 8090;
    my $interval  	= 180;

    $hash->{HOST} 	= $host;
    $hash->{PORT} 	= $port;
    $hash->{INTERVAL} 	= $interval;
    $hash->{VERSION} 	= $version;
    $hash->{helper}{infoErrorCounter} = 0;
    $hash->{helper}{setCmdErrorCounter} = 0;

    Log3 $name, 3, "AMAD ($name) - defined with host $hash->{HOST} on port $hash->{HOST} and interval $hash->{INTERVAL} (sec)";

    AMAD_GetUpdateLocal( $hash );

    InternalTimer( gettimeofday()+$hash->{INTERVAL}, "AMAD_GetUpdateTimer", $hash, 0 );
    
    $hash->{STATE} = "initialized";
    readingsSingleUpdate  ( $hash, "deviceState", "online", 0 );

    return undef;
}

sub AMAD_Undef($$) {

my ( $hash, $arg ) = @_;

    RemoveInternalTimer( $hash );

    return undef;
}

sub AMAD_Attr(@) {

my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    if( $attrName eq "disable" ) {
	if( $cmd eq "set" ) {
	    if( $attrVal eq "0" ) {
		RemoveInternalTimer( $hash );
		InternalTimer( gettimeofday()+2, "AMAD_GetUpdateTimer", $hash, 0 ) if( $hash->{STATE} eq "disabled" );
		$hash->{STATE}='active';
		Log3 $name, 3, "AMAD ($name) - enabled";
	    } else {
		$hash->{STATE} = 'disabled';
		RemoveInternalTimer( $hash );
		Log3 $name, 3, "AMAD ($name) - disabled";
	    }
	}
	elsif( $cmd eq "del" ) {
	    RemoveInternalTimer( $hash );
	    InternalTimer( gettimeofday()+2, "AMAD_GetUpdateTimer", $hash, 0 ) if( $hash->{STATE} eq "disabled" );
	    $hash->{STATE}='active';
	    Log3 $name, 3, "AMAD ($name) - enabled";

	} else {
	    if($cmd eq "set") {
		$attr{$name}{$attrName} = $attrVal;
		Log3 $name, 3, "AMAD ($name) - $attrName : $attrVal";
	    }
	    elsif( $cmd eq "del" ) {
	    }
	}
    }
    
    if( $attrName eq "interval" ) {
	if( $cmd eq "set" ) {
	    if( $attrVal < 60 ) {
		Log3 $name, 3, "AMAD ($name) - interval too small, please use something > 60 (sec), default is 180 (sec)";
		return "interval too small, please use something > 60 (sec), default is 180 (sec)";
	    } else {
		$hash->{INTERVAL} = $attrVal;
		Log3 $name, 3, "AMAD ($name) - set interval to $attrVal";
	    }
	}
	elsif( $cmd eq "del" ) {
	    $hash->{INTERVAL} = 180;
	    Log3 $name, 3, "AMAD ($name) - set interval to default";
	
	} else {
	    if( $cmd eq "set" ) {
		$attr{$name}{$attrName} = $attrVal;
		Log3 $name, 3, "AMAD ($name) - $attrName : $attrVal";
	    }
	    elsif( $cmd eq "del" ) {
	    }
	}
    }
    
    if( $attrName eq "port" ) {
	if( $cmd eq "set" ) {
	    $hash->{PORT} = $attrVal;
	    Log3 $name, 3, "AMAD ($name) - set port to $attrVal";
	}
	elsif( $cmd eq "del" ) {
	    $hash->{PORT} = 8090;
	    Log3 $name, 3, "AMAD ($name) - set port to default";
	
	} else {
	    if( $cmd eq "set" ) {
		$attr{$name}{$attrName} = $attrVal;
		Log3 $name, 3, "AMAD ($name) - $attrName : $attrVal";
	    }
	    elsif( $cmd eq "del" ) {
	    }
	}
    }

    return undef;
}

sub AMAD_GetUpdateLocal($) {

my ( $hash ) = @_;
    my $name = $hash->{NAME};

    AMAD_RetrieveAutomagicInfo( $hash ) if( ReadingsVal( $name, "deviceState", "online" ) eq "online" && $hash->{STATE} ne "initialized" && AttrVal( $name, "disable", 0 ) ne "1" );  ### deviceState muß von Hand online/offline gesetzt werden z.B. über RESIDENZ Modul
    
    return 1;
}

sub AMAD_GetUpdateTimer($) {

    my ( $hash ) = @_;
    my $name = $hash->{NAME};
 
    AMAD_RetrieveAutomagicInfo( $hash ) if( ReadingsVal( $name, "deviceState", "online" ) eq "online" && AttrVal( $name, "disable", 0 ) ne "1" );  ### deviceState muß von Hand online/offline gesetzt werden z.B. über RESIDENZ Modul
  
    InternalTimer( gettimeofday()+$hash->{INTERVAL}, "AMAD_GetUpdateTimer", $hash, 1 );
    Log3 $name, 4, "AMAD ($name) - Call AMAD_GetUpdateTimer";

    return 1;
}

sub AMAD_Set($$@) {
    
    my ( $hash, $name, $cmd, @val ) = @_;
    my $apps = AttrVal( $name, "setOpenApp", "none" );
  
    my $list = "";
    
    $list .= "screenMsg ";
    $list .= "ttsMsg ";
    $list .= "volume:slider,0,1,15 ";
    $list .= "deviceState:online,offline ";
    $list .= "mediaPlayer:play,stop,next,back " if( AttrVal( $name, "fhemServerIP", "none" ) ne "none" );
    $list .= "screenBrightness:slider,0,1,255 " if( AttrVal( $name, "setScreenBrightness", "1" ) eq "1" );
    $list .= "screen:on,off ";
    $list .= "screenOrientation:auto,landscape,portrait " if( AttrVal( $name, "setScreenOrientation", "1" ) eq "1" );
    $list .= "screenFullscreen:on,off " if( AttrVal( $name, "setFullscreen", "1" ) eq "1" );
    $list .= "openURL ";
    $list .= "openApp:$apps " if( AttrVal( $name, "setOpenApp", "none" ) ne "none" );
    $list .= "nextAlarmTime:time ";
    $list .= "statusRequest:noArg ";
    $list .= "system:reboot " if( AttrVal( $name, "root", "1" ) eq "1" );


    if (lc $cmd eq 'screenmsg'
	|| lc $cmd eq 'ttsmsg'
	|| lc $cmd eq 'volume'
	|| lc $cmd eq 'mediaplayer'
	|| lc $cmd eq 'devicestate'
	|| lc $cmd eq 'screenbrightness'
	|| lc $cmd eq 'screenorientation'
	|| lc $cmd eq 'screenfullscreen'
	|| lc $cmd eq 'screen'
	|| lc $cmd eq 'openurl'
	|| lc $cmd eq 'openapp'
	|| lc $cmd eq 'nextalarmtime'
	|| lc $cmd eq 'system'
	|| lc $cmd eq 'statusrequest') {

	    Log3 $name, 5, "AMAD ($name) - set $name $cmd ".join(" ", @val);
	  
	    return "set command only works if STATE not equal initialized, please wait for next interval run" if( $hash->{STATE} eq "initialized");
	    return "Cannot set command, FHEM Device is disabled" if( AttrVal( $name, "disable", "0" ) eq "1" );
	    
	    return AMAD_SelectSetCmd( $hash, $cmd, @val ) if( @val ) && ( ReadingsVal( $name, "deviceState", "online" ) eq "offline" ) && ( lc $cmd eq 'devicestate' );
	    return "Cannot set command, FHEM Device is offline" if( ReadingsVal( $name, "deviceState", "online" ) eq "offline" );
	  
	    return AMAD_SelectSetCmd( $hash, $cmd, @val ) if( @val ) || ( lc $cmd eq 'statusrequest' );
    }

    return "Unknown argument $cmd, bearword as argument or wrong parameter(s), choose one of $list";
}

sub AMAD_RetrieveAutomagicInfo($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $host = $hash->{HOST};
    my $port = $hash->{PORT};
    my $fhemip = AttrVal( $name, "fhemServerIP", "none" );

    my $url = "http://" . $host . ":" . $port . "/fhem-amad/deviceInfo/"; # Path muß so im Automagic als http request Trigger drin stehen
  
    HttpUtils_NonblockingGet(
	{
	    url		=> $url,
	    timeout	=> 5,
	    hash	=> $hash,
	    method	=> "GET",
	    header	=> "fhemIP: $fhemip\r\nfhemDevice: $name",
	    doTrigger	=> 1,
	    callback	=> \&AMAD_RetrieveAutomagicInfoFinished,
	}
    );
    Log3 $name, 4, "AMAD ($name) - NonblockingGet get URL";
    Log3 $name, 4, "AMAD ($name) - AMAD_RetrieveAutomagicInfo: calling Host: $host";
}

sub AMAD_RetrieveAutomagicInfoFinished($$$) {
    
    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $doTrigger = $param->{doTrigger};
    my $name = $hash->{NAME};
    my $host = $hash->{HOST};

    Log3 $name, 4, "AMAD ($name) - AMAD_RetrieveAutomagicInfoFinished: processed request data";
    


    ### Begin Error Handling
    if( $hash->{helper}{infoErrorCounter} > 2 ) {
	readingsBeginUpdate( $hash );
	readingsBulkUpdate( $hash, "lastStatusRequestState", "statusRequest_error" );
	
	if( ReadingsVal( $name, "flow_Informations", "active" ) eq "inactive" && ReadingsVal( $name, "flow_SetCommands", "active" ) eq "inactive" ) {
	    readingsBulkUpdate( $hash, "lastStatusRequestError", "AMAD flows on your device inactive, please check your device" );
	    
	    Log3 $name, 5, "AMAD ($name) - CHECK THE LAST ERROR READINGS FOR MORE INFO, DEVICE IS SET OFFLINE";
	     
	    readingsBulkUpdate( $hash, "deviceState", "offline" );
	    $hash->{STATE} = "AMAD Flows inactive, device set offline";
	}
	elsif( $hash->{helper}{infoErrorCounter} > 4 && $hash->{helper}{setCmdErrorCounter} > 2 ) {
	    readingsBulkUpdate( $hash, "lastStatusRequestError", "to many errors, check your network or device configuration" );
	    
	    Log3 $name, 4, "AMAD ($name) - To many Errors please check your Network or Device Configuration, DEVICE IS SET OFFLINE";
	    
	    readingsBulkUpdate( $hash, "deviceState", "offline" );
	    $hash->{STATE} = "To many Errors, device set offline";
	}
	elsif( ReadingsVal( $name, "flow_Informations", "active" ) eq "inactive" ) {
	    readingsBulkUpdate( $hash, "lastStatusRequestError", "informations flow on your device is inactive, will try to reactivate" );
	    
	    Log3 $name, 4, "AMAD ($name) - Informations Flow on your Device is inactive, will try to reactivate";
	}
	elsif($hash->{helper}{infoErrorCounter} > 4 && ReadingsVal( $name, "flow_Informations", "active" ) eq "active" ){
	    readingsBulkUpdate( $hash, "lastStatusRequestError", "check automagicApp on your device" );
	    
	    Log3 $name, 4, "AMAD ($name) - Please check the AutomagicAPP on your Device";
	} else {
	    readingsBulkUpdate( $hash, "lastStatusRequestError", "unknown error, please contact the developer" );
	    
	    Log3 $name, 4, "AMAD ($name) - UNKNOWN ERROR, PLEASE CONTACT THE DEVELOPER, DEVICE DISABLED";
	    
	    $hash->{STATE} = "Unknown Error, device disabled";
	    
	    $attr{$name}{disable} = 1;
	}
	readingsEndUpdate( $hash, 1 );
    }
    
    if( defined( $err ) ) {
	if( $err ne "" ) {
	    $hash->{STATE} = $err if( $hash->{STATE} ne "initialized" );
	    $hash->{helper}{infoErrorCounter} = ( $hash->{helper}{infoErrorCounter} + 1 );

	    readingsBeginUpdate( $hash );
	    readingsBulkUpdate( $hash, "lastStatusRequestState", "statusRequest_error" );
	  
	    if( $err =~ /timed out/ ) {
		readingsBulkUpdate( $hash, "lastStatusRequestError", "connect to your device is timed out. check network ");
	    }
	    elsif( ( $err =~ /Keine Route zum Zielrechner/ ) && $hash->{helper}{infoErrorCounter} > 1 ) {
		readingsBulkUpdate( $hash,"lastStatusRequestError", "no route to target. bad network configuration or network is down ");
	    } else {
		readingsBulkUpdate($hash, "lastStatusRequestError", "$err" );
	    }

	readingsEndUpdate( $hash, 1 );
	
	Log3 $name, 4, "AMAD ($name) - AMAD_RetrieveAutomagicInfoFinished: error while requesting AutomagicInfo: $err";
	return;
	}
    }

    if( $data eq "" and exists( $param->{code} ) ) {
	$hash->{STATE} = $param->{code} if( $hash->{STATE} ne "initialized" );
	$hash->{helper}{infoErrorCounter} = ( $hash->{helper}{infoErrorCounter} + 1 );
    
	readingsBeginUpdate( $hash );
	readingsBulkUpdate( $hash, "lastStatusRequestState", "statusRequest_error" );
    
	if( $param->{code} ne 200 ) {
	    readingsBulkUpdate( $hash," lastStatusRequestError", "http Error ".$param->{code} );
	}
	
	readingsBulkUpdate( $hash, "lastStatusRequestError", "empty response, check automagicApp on your device" );
	readingsEndUpdate( $hash, 1 );
    
	Log3 $name, 4, "AMAD ($name) - AMAD_RetrieveAutomagicInfoFinished: received http code ".$param->{code}." without any data after requesting AMAD AutomagicInfo";

	return;
    }

    if( ( $data =~ /Error/i ) and exists( $param->{code} ) ) {    
	$hash->{STATE} = $param->{code} if( $hash->{STATE} ne "initialized" );
	$hash->{helper}{infoErrorCounter} = ( $hash->{helper}{infoErrorCounter} + 1 );

	readingsBeginUpdate( $hash );
	readingsBulkUpdate( $hash, "lastStatusRequestState", "statusRequest_error" );
    
	    if( $param->{code} eq 404 && ReadingsVal( $name, "flow_Informations", "inactive" ) eq "inactive" ) {
		readingsBulkUpdate( $hash, "lastStatusRequestError", "check the informations flow on your device" );
	    }
	    elsif( $param->{code} eq 404 && ReadingsVal( $name, "flow_Informations", "active" ) eq "active" ) {
		readingsBulkUpdate( $hash, "lastStatusRequestError", "check the automagicApp on your device" );
	    } else {
		readingsBulkUpdate( $hash, "lastStatusRequestError", "http error ".$param->{code} );
	    }
	
	readingsEndUpdate( $hash, 1 );
    
	Log3 $name, 4, "AMAD ($name) - AMAD_RetrieveAutomagicInfoFinished: received http code ".$param->{code}." receive Error after requesting AMAD AutomagicInfo";

	return;
    }

    ### End Error Handling

    $hash->{helper}{infoErrorCounter} = 0;
 
    ### Begin Response Processing
    $hash->{STATE} = "active" if( $hash->{STATE} eq "initialized" || $hash->{STATE} ne "active" );
    
    my @valuestring = split( '@@@@',  $data );
    my %buffer;
    foreach( @valuestring ) {
	my @values = split( '@@' , $_ );
	$buffer{$values[0]} = $values[1];
    }


    readingsBeginUpdate( $hash );
    
    my $t;
    my $v;
    while( ( $t, $v ) = each %buffer ) {
	$v =~ s/null//g;
	readingsBulkUpdate( $hash, $t, $v ) if( defined( $v ) );
    }
    
    readingsBulkUpdate( $hash, "lastStatusRequestState", "statusRequest_done" );
    
    readingsEndUpdate( $hash, 1 );
    
    $hash->{helper}{infoErrorCounter} = 0;
    ### End Response Processing
    
    $hash->{STATE} = "active" if( $hash->{STATE} eq "initialized" );
    
    return undef;
}

sub AMAD_HTTP_POST($$) {

    my ( $hash, $url ) = @_;
    my $name = $hash->{NAME};
    
    my $state = $hash->{STATE};
    
    $hash->{STATE} = "Send HTTP POST";
    
    HttpUtils_NonblockingGet(
	{
	    url		=> $url,
	    timeout	=> 5,
	    hash	=> $hash,
	    method	=> "POST",
	    doTrigger	=> 1,
	    callback	=> \&AMAD_HTTP_POSTerrorHandling,
	}
    );
    Log3 $name, 4, "AMAD ($name) - Send HTTP POST with URL $url";

    $hash->{STATE} = $state;

    return undef;
}

sub AMAD_HTTP_POSTerrorHandling($$$) {

    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    

    ### Begin Error Handling
    if( $hash->{helper}{setCmdErrorCounter} > 2 ) {
	readingsBeginUpdate( $hash );
	readingsBulkUpdate( $hash, "lastSetCommandState", "statusRequest_error" );
	
	if( ReadingsVal( $name, "flow_Informations", "active" ) eq "inactive" && ReadingsVal( $name, "flow_SetCommands", "active" ) eq "inactive" ) {
	    readingsBulkUpdate( $hash, "lastSetCommandError", "AMAD flows on your device inactive, please check your device" );
	    Log3 $name, 5, "AMAD ($name) - CHECK THE LAST ERROR READINGS FOR MORE INFO, DEVICE IS SET OFFLINE";
	     
	    readingsBulkUpdate( $hash, "deviceState", "offline" );
	    $hash->{STATE} = "AMAD Flows inactive, device set offline";
	}
	elsif( $hash->{helper}{infoErrorCounter} > 4 && $hash->{helper}{setCmdErrorCounter} > 2 ) {
	    readingsBulkUpdate($hash, "lastSetCommandError", "to many errors, check your network or device configuration" );
	    
	    Log3 $name, 4, "AMAD ($name) - To many Errors please check your Network or Device Configuration, DEVICE IS SET OFFLINE";
	    
	    readingsBulkUpdate( $hash, "deviceState", "offline" );
	    $hash->{STATE} = "To many Errors, device set offline";
	}
	elsif( ReadingsVal( $name, "flow_SetCommands", "active" ) eq "inactive" ) {
	    readingsBulkUpdate( $hash, "lastSetCommandError", "setCommands flow on your device is inactive, will try to reactivate" );
	    
	    Log3 $name, 4, "AMAD ($name) - Flow SetCommands on your Device is inactive, will try to reactivate";
	}
	elsif( $hash->{helper}{setCmdErrorCounter} > 4 && ReadingsVal( $name, "flow_SetCommands", "active" ) eq "active" ){
	    readingsBulkUpdate( $hash, "lastSetCommandError", "check automagicApp on your device" );
	    
	    Log3 $name, 4, "AMAD ($name) - Please check the AutomagicAPP on your Device";
	} 
	elsif( $hash->{helper}{setCmdErrorCounter} > 4 ) {
	    readingsBulkUpdate( $hash, "lastSetCommandError", "unknown error, please contact the developer" );
	    
	    Log3 $name, 4, "AMAD ($name) - UNKNOWN ERROR, PLEASE CONTACT THE DEVELOPER, DEVICE DISABLED";
	    
	    $hash->{STATE} = "Unknown Error, device disabled";
	    
	    $attr{$name}{disable} = 1;
	}
	readingsEndUpdate( $hash, 1 );
    }
    
    if( defined( $err ) ) {
	if( $err ne "" ) {
	  $hash->{STATE} = $err if( $hash->{STATE} ne "initialized" );
	  $hash->{helper}{setCmdErrorCounter} = ($hash->{helper}{setCmdErrorCounter} + 1);
	  
	  readingsBeginUpdate( $hash );
	  readingsBulkUpdate( $hash, "lastSetCommandState", "cmd_error" );
	  
	  if( $err =~ /timed out/ ) {
	      readingsBulkUpdate( $hash, "lastSetCommandError", "connect to your device is timed out. check network" );
	  }
	  elsif( $err =~ /Keine Route zum Zielrechner/ ) {
	      readingsBulkUpdate( $hash, "lastSetCommandError", "no route to target. bad network configuration or network is down" );
	  } else {
	      readingsBulkUpdate( $hash, "lastSetCommandError", "$err" );
	  }
	  readingsEndUpdate( $hash, 1 );
	  
	  Log3 $name, 5, "AMAD ($name) - AMAD_HTTP_POST: error while POST Command: $err";
	  
	  return;
	}
    }
 
    if( $data eq "" and exists( $param->{code} ) && $param->{code} ne 200 ) {
	$hash->{STATE} = $param->{code} if( $hash->{STATE} ne "initialized" );
	$hash->{helper}{setCmdErrorCounter} = ( $hash->{helper}{setCmdErrorCounter} + 1 );
    
	readingsBeginUpdate( $hash );
	readingsBulkUpdate($hash, "lastSetCommandState", "cmd_error" );
	readingsBulkUpdate($hash, "lastSetCommandError", "http Error ".$param->{code} );
	readingsEndUpdate( $hash, 1 );
    
	Log3 $name, 5, "AMAD ($name) - AMAD_HTTP_POST: received http code ".$param->{code};

	return;
    }
        
    if( ( $data =~ /Error/i ) and exists( $param->{code} ) ) {    
	$hash->{STATE} = $param->{code} if( $hash->{STATE} ne "initialized" );
	$hash->{helper}{setCmdErrorCounter} = ( $hash->{helper}{setCmdErrorCounter} + 1 );
    
	readingsBeginUpdate( $hash );
	readingsBulkUpdate( $hash, "lastSetCommandState", "cmd_error" );
    
	    if( $param->{code} eq 404 ) {
		readingsBulkUpdate( $hash, "lastSetCommandError", "setCommands flow is inactive on your device!" );
	    } else {
		readingsBulkUpdate( $hash, "lastSetCommandError", "http error ".$param->{code} );
	    }
	readingsEndUpdate( $hash, 1 );
	
	return;
    }
    
    ### End Error Handling
    
    readingsSingleUpdate( $hash, "lastSetCommandState", "cmd_done", 1 );
    $hash->{helper}{infoErrorCounter} = 0;
    
    Log3 $name, 4, "AMAD ($name) - Starte Update GetUpdateLocal";
    AMAD_GetUpdateLocal( $hash );
    
    return undef;
}

sub AMAD_SelectSetCmd($$@) {

    my ( $hash, $cmd, @data ) = @_;
    my $name = $hash->{NAME};
    my $host = $hash->{HOST};
    my $port = $hash->{PORT};

    if( lc $cmd eq 'screenmsg' ) {
	my $msg = join( " ", @data );
	
	$msg =~ s/%/%25/g;
	$msg =~ s/\s/%20/g;
	
	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/screenMsg?message=$msg";
	Log3 $name, 4, "AMAD ($name) - Sub AMAD_SetScreenMsg";

	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'ttsmsg' ) {
	my $msg = join( " ", @data );
	
	$msg =~ s/%/%25/g;
	$msg =~ s/\s/%20/g;    
	
	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/ttsMsg?message=$msg";
    
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'volume' ) {
	my $vol = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/setVolume?volume=$vol";

	readingsSingleUpdate( $hash, $cmd, $vol, 1 );
	
	return AMAD_HTTP_POST( $hash, $url );
    }
    
    elsif( lc $cmd eq 'mediaplayer' ) {
	my $btn = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/mediaPlayer?button=$btn";
    
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'devicestate' ) {
	my $v = join( " ", @data );

	readingsSingleUpdate( $hash, $cmd, $v, 1 );
      
	return undef;
    }
    
    elsif( lc $cmd eq 'screenbrightness' ) {
	my $bri = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/setBrightness?brightness=$bri";
    
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'screen' ) {
	my $mod = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/setScreenOnOff?screen=$mod";

	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'screenorientation' ) {
	my $mod = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/setScreenOrientation?orientation=$mod";

	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'screenfullscreen' ) {
	my $mod = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/setScreenFullscreen?fullscreen=$mod";

	readingsSingleUpdate( $hash, $cmd, $mod, 1 );
	
	return AMAD_HTTP_POST( $hash, $url );
    }
    
    elsif( lc $cmd eq 'openurl' ) {
	my $openurl = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/openURL?url=$openurl";
    
	return AMAD_HTTP_POST( $hash, $url );
    }
    
    elsif (lc $cmd eq 'nextalarmtime') {
	my $alarmTime = join( " ", @data );
	my @alarm = split( ":", $alarmTime );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/setAlarm?hour=".$alarm[0]."&minute=".$alarm[1];
    
	return AMAD_HTTP_POST( $hash, $url );
    }
    
    elsif( lc $cmd eq 'statusrequest' ) {
	AMAD_GetUpdateLocal( $hash );
	return undef;
    }
    
    elsif( lc $cmd eq 'openapp' ) {
	my $app = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/openApp?app=$app";
    
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'system' ) {
	my $systemcmd = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/systemcommand?syscmd=$systemcmd";
    
	return AMAD_HTTP_POST( $hash,$url );
    }

    return undef;
}


1;


=pod
=begin html

<a name="AMAD"></a>
<h3>AMAD</h3>
<ul>
  <u><b>AMAD - Automagic Android Device</b></u>
  At the moment no english documentation is available
</ul>

=end html
=begin html_DE

<a name="AMAD"></a>
<h3>AMAD</h3>
<ul>
  <u><b>AMAD - Automagic Android Device</b></u>
  Dieses Modul liefert, <b><u>in Verbindung mit der Android APP Automagic</u></b>, diverse Informationen von Android Ger&auml;ten.
  Die AndroidAPP Automagic (welche nicht von mir stammt und 2.90Euro kostet) funktioniert wie Tasker, ist aber bei weitem User freundlicher.
  Im Auslieferiungszustand werden folgende Zust&auml;nde dargestellt:
  <ul>
    <li>Zustand von Automagic auf dem Ger&auml;t</li>
    <li>Bluetooth An/Aus</li>
    <li>verbundene Bluetoothger&auml;te</li>
    <li>aktuell abgespieltes Musikalbum des verwendeten Mediaplayers</li>
    <li>aktuell abgespielter Musikinterpret des verwendeten Mediaplayers</li>
    <li>aktuell abgespielter Musiktitel des verwendeten Mediaplayers</li>
    <li>Status des Androidger&auml;tes - Online/Offline</li>
    <li>n&auml;chster Alarmtag</li>
    <li>n&auml;chste Alarmzeit</li>
    <li>Batteriestatus in %</li>
    <li>Ladestatus - Netztei angeschlossen / nicht angeschlossen</li>
    <li>Bildschirnstatus An/Aus</li>
    <li>Bildschirmhelligkeit</li>
    <li>Vollbildmodus An/Aus</li>
    <li>Bildschirmausrichtung Auto/Landscape/Portrait</li>
    <li>Standardlautst&auml;rke</li>
    <li>Media Lautst&auml;rke des Lautsprechers am Ger&auml;t</li>
    <li>Media Lautst&auml;rke des Bluetooth Lautsprechers</li>
  </ul>
  <br>
  Mit etwas Einarbeitung k&ouml;nnen jegliche Informationen welche Automagic bereit stellt in FHEM angezeigt werden. Hierzu bedarf es lediglich
  einer kleinen Anpassung des "Informations" Flows
  <br><br>
  Das Modul gibt Dir auch die M&ouml;glichkeit Deine Androidger&auml;te zu steuern. So k&ouml;nnen folgende Aktionen durchgef&uuml;hrt werden.
  <ul>
    <li>Status des Ger&auml;tes (Online,Offline)</li>
    <li>Mediaplayer steuern (Play, Stop, n&auml;chster Titel, vorheriger Titel)</li>
    <li>n&auml;chste Alarmzeit setzen</li>
    <li>eine App auf dem Ger&auml;t &ouml;ffnen</li>
    <li>eine URL im Browser &ouml;ffnen</li>
    <li>Bildschirm An/Aus machen</li>
    <li>Bildschirmhelligkeit einstellen</li>
    <li>Vollbildmodus einschalten</li>
    <li>eine Nachricht senden welche am Bildschirm angezeigt wird</li>
    <li>Bildschirmausrichtung einstellen (Auto,Landscape,Portrait)</li>
    <li>neuen Statusreport des Ger&auml;tes anfordern</li>
    <li>Systembefehle setzen (Reboot)</li>
    <li>eine Nachricht senden welche <b>angesagt</b> wird (TTS)</li>
    <li>Medienlautst&auml;rke regeln</li>  
  </ul>
  <br><br> 
  F&uuml;r all diese Aktionen und Informationen wird auf dem Androidger&auml;t Automagic und ein so genannter Flow ben&ouml;tigt. Die App m&uuml;&szlig;t
  Ihr Euch besorgen, die Flows bekommt Ihr von mir zusammen mit dem AMAD Modul.
  <br><br>
  <b>Wie genau verwendet man nun AMAD?</b>
  <ul>
    <li>installiert Euch die App "Automagic Premium" aus dem App Store oder die Testversion von <a href="https://automagic4android.com/de/testversion">hier</a></li>
    <li>installiert das Flowset 74_AMADautomagicFlows$VERSION.xml aus dem Ordner $INSTALLFHEM/FHEM/lib/ auf Eurem Androidger&auml;t und aktiviert erstmal nur den "Informations" Flow.</li>
  </ul>
  <br>
  Nun m&uuml;sst Ihr nur noch ein Device in FHEM anlegen.
  <br><br>
  <a name="AMADdefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; AMAD &lt;IP-ADRESSE&gt;</code>
    <br><br>
    Beispiel:
    <ul><br>
      <code>define WandTabletWohnzimmer AMAD 192.168.0.23</code><br>
    </ul>
    <br>
    Diese Anweisung erstellt ein neues AMAD-Device. Der Parameter &lt;IP-ADRESSE&lt; legt die IP Adresse des Android Ger&auml;tes fest.<br>
    Das Standard Abfrageinterval ist 180 Sekunden und kann &uuml;ber das Attribut intervall ge&auml;ndert werden. Wer den Port &auml;ndern m&ouml;chte, kann dies &uuml;ber
    das Attribut port tun. <b>Ihr solltet aber wissen was Ihr tut, da dieser Port im HTTP Response Trigger der beiden Flows eingestellt ist. Demzufolge mu&szlig; dieser dort
    auch ver&auml;dert werden.</b><br>
  </ul>
  <br><br> 
  <b><u>Fertig! Nach anlegen der Ger&auml;teinstanz sollten nach sp&auml;testens 3 Minuten bereits die ersten Readings reinkommen.</u></b>
  <br><br>
  <a name="AMADreadings"></a>
  <b>Readings</b>
  <ul>
    <li>automagicState - Statusmeldungen von der AutomagicApp</li>
    <li>bluetooth on/off - ist auf dem Ger&auml;t Bluetooth an oder aus</li>
    <li>connectedBTdevices - eine Lieste der verbundenen Ger&auml;t</li>
    <li>currentMusicAlbum - aktuell abgespieltes Musikalbum des verwendeten Mediaplayers</li>
    <li>currentMusicArtist - aktuell abgespielter Musikinterpret des verwendeten Mediaplayers</li>
    <li>currentMusicTrack - aktuell abgespielter Musiktitel des verwendeten Mediaplayers</li>
    <li>deviceState - Status des Androidger&auml;tes, muss selbst mit setreading gesetzt werden z.B. &uuml;ber die Anwesenheitskontrolle.<br>
    Ist Offline gesetzt, wird der Intervall zum Informationsabruf aus gesetzt.</li>
    <li>flow_SetCommands active/inactive - gibt den Status des SetCommands Flow wieder</li>
    <li>flow_informations active/inactive - gibt den Status des Informations Flow wieder</li>
    <li>lastSetCommandError - letzte Fehlermeldung vom set Befehl</li>
    <li>lastSetCommandState - letzter Status vom set Befehl, Befehl erfolgreich/nicht erfolgreich gesendet</li>
    <li>lastStatusRequestError - letzte Fehlermeldung vom statusRequest Befehl</li>
    <li>lastStatusRequestState - letzter Status vom statusRequest Befehl, Befehl erfolgreich/nicht erfolgreich gesendet</li>
    <li>nextAlarmDay - aktiver Alarmtag</li>
    <li>nextAlarmTime - aktive Alarmzeit</li>
    <li>powerLevel - Status der Batterie in %</li>
    <li>powerPlugged - Netzteil angeschlossen? 0=NEIN, 2=JA</li>
    <li>screen - Bildschirm An oderAus</li>
    <li>screenBrightness - Bildschirmhelligkeit von 0-255</li>
    <li>screenFullscreen - Vollbildmodus (On,Off)</li>
    <li>screenOrientation - Bildschirmausrichtung (Auto,Landscape,Portrait)</li>
    <li>volume - Lautst&auml;rkewert welcher &uuml;ber "set volume" gesetzt wurde.</li>
    <li>volumeMusikBluetooth - Media Lautst&auml;rke von angeschlossenden Bluetooth Lautsprechern</li>
    <li>volumeMusikSpeaker - Media Lautst&auml;rke der internen Lautsprecher</li>
    <br>
    Die Readings volumeMusikBluetooth und volumeMusikSpeaker spiegeln die jeweilige Medialautst&auml;rke der angeschlossenden Bluetoothlautsprechern oder der internen Lautsprecher wieder.<br>
    Sofern man die jeweiligen Lautst&auml;rken ausschlie&szlig;lich &uuml;ber den Set Befehl setzt, wird eine der beiden immer mit dem "volume" Reading &uuml;ber ein stimmen.<br><br>
  </ul>
  <br><br>
  <a name="AMADset"></a>
  <b>Set</b>
  <ul>
    <li>deviceState - setzt den Device Status Online/Offline. Siehe Readings</li>
    <li>mediaPlayer - steuert den Standard Mediaplayer. play, stop, Titel z&uuml;r&uuml;ck, Titel vor.</li>
    <li>nextAlarmTime - setzt die Alarmzeit. Geht aber nur innerhalb der n&auml;chsten 24Std.</li>
    <li>openURL - &ouml;ffnet eine URL im Standardbrowser</li>
    <li>screen - setzt den Bildschirm on/off mit Sperre, in den Automagic Einstellungen muss "Admin Funktion" gesetzt werden sonst funktioniert "Screen off" nicht.</li>
    <li>screenMsg - versendet eine Bildschirmnachricht</li>
    <li>statusRequest - Fordert einen neuen Statusreport beim Device an</li>
    <li>ttsMsg - versendet eine Nachricht welche als Sprachnachricht ausgegeben wird</li>
    <li>volume - setzt die Medialautst&auml;rke. Entweder die internen Lautsprecher oder sofern angeschlossen die Bluetoothlautsprecher</li>
  </ul>
  <br>
  <b>Set abh&auml;ngig von gesetzten Attributen</b>
  <ul>
    <li>mediaPlayer - steuert den Standard Mediaplayer. play, stop, Titel z&uuml;r&uuml;ck, Titel vor. <b>Attribut fhemServerIP</b></li>
    <li>openApp - &ouml;ffnet eine ausgew&auml;hlte App. <b>Attribut setOpenApp</b></li>
    <li>screenBrightness - setzt die Bildschirmhelligkeit, von 0-255 <b>Attribut setScreenBrightness</b></li>
    Wenn Ihr das "set screenBrightness" verwenden wollt, muss eine kleine Anpassung im Flow SetCommands vorgenommen werden. &Ouml;ffnet die Aktion (eines der Vierecke ganz ganz unten)
    SetzeSystemeinstellung:System und macht einen Haken bei "Ich habe die Einstellungen &uuml;berpr&uuml;ft, ich weiss was ich tue".
    <li>screenFullscreen - Schaltet den Vollbildmodus on/off. <b>Attribut setFullscreen</b></li>
    <li>screenOrientation - Schaltet die Bildschirmausrichtung Auto/Landscape/Portait. <b>Attribut setScreenOrientation</b></li>
    <li>system - setzt Systembefehle ab (nur bei gerootetet Ger&auml;en). Reboot <b>Attribut root</b>, in den Automagic Einstellungen muss "Root Funktion" gesetzt werden</li>
    Um openApp verwenden zu k&ouml;nnen, muss als Attribut ein, oder durch Komma getrennt, mehrere App Namen gesetzt werden. Der App Name ist frei w&auml;hlbar und nur zur Wiedererkennung notwendig.
    Der selbe App Name mu&szlig; im Flow SetCommands auf der linken Seite unterhalb der Raute Expression:"openApp" in einen der 5 Str&auml;nge (eine App pro Strang) in beide Rauten eingetragen werden. Danach wird
    in das
    Viereck die App ausgew&auml;lt welche durch den Attribut App Namen gestartet werden soll.
  </ul>
  <br><br>
  <a name="AMADstate"></a>
  <b>STATE</b>
  <ul>
    <li>initialized - Ist der Status kurz nach einem define..</li>
    <li>active - die Ger&auml;teinstanz ist im aktiven Status.</li>
    <li>disabled - die Ger&auml;teinstanz wurde &uuml;ber das Attribut disable deaktiviert</li>
  </ul>
  <br><br><br>
  <u><b>Anwendungsbeispiele:</b></u>
  <ul><br>
    Ich habe die Ladeger&auml;te f&uuml;r meine Androidger&auml;te an Funkschaltsteckdosen. ein DOIF schaltet bei unter 30% die Steckdose ein und bei &uuml;ber 90% wieder aus. Morgens lasse ich mich
    &uuml;ber mein Tablet im Schlafzimmer mit Musik wecken. Verwendet wird hierzu der wakeuptimer des RESIDENTS Modules. Das abspielen stoppe ich dann von Hand. Danach erfolgt noch eine
    Ansage wie das Wetter gerade ist und wird.<br>
    Mein 10" Tablet im Wohnzimmer ist Mediaplayer f&uuml;r das Wohnzimmer mit Bluetoothlautsprechern. Die Lautst&auml;rke wird automatisch runter gesetzt wenn die Fritzbox einen Anruf auf das
    Wohnzimmer Handger&auml;t signalisiert.
  </ul>
  <br><br><br>
  <b><u>Und zu guter letzt m&ouml;chte ich mich noch bedanken.</u><br>
  Der gr&ouml;&szlig;te Dank geht an meinen Mentor Andre (justme1968), er hat mir mit hilfreichen Tips geholfen Perlcode zu verstehen und Spa&szlig; am programmieren zu haben.<br>
  Auch m&ouml;chte ich mich bei Jens bedanken (jensb) welcher mir ebenfalls mit hilfreichen Tips bei meinen aller ersten Gehversuchen beim Perlcode schreiben unterst&uuml;tzt hat.<br>
  So und nun noch ein besonderer Dank an pah (Prof. Dr. Peter Henning ), ohne seine Aussage "Keine Ahnung hatten wir alle mal, das ist keine Ausrede" h&auml;tte ich bestimmt nicht angefangen Interesse an
  Modulentwicklung zu zeigen :-)</b>
</ul>

=end html_DE
=cut