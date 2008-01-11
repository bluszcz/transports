use strict;
use LWP::UserAgent;
use HTTP::Request::Common qw(GET POST);
use HTTP::Response;
use Unicode::Lite;

my $PLUGIN_NAME			= "EraOmnix_Platna";
my $PLUGIN_VERSION		= "0.2";
my $DEFAULT_PRIO		= 5;
my $DEST_NUMBERS_REGEXP		=  '^\+[0-9]+'; # needed linke this in // good numberz? any, they say

use vars qw ( %EraOmnix_Plat_accounts );

# RULES:
# 1. ALWAYS, ALWAYS, ALWAYS create new presence/message/iq
# 2. Create handlers, plugin is named ser.vi.ce/Plugin
# 3. Provide ALL info into %plugin_data

RegisterEvent('iq','^'.$config{service_name}."/".$PLUGIN_NAME.'$',\&EraOmnix_Plat_InIQ); # for registration
RegisterEvent('pre_connect','.+',\&EraOmnix_Plat_PreConn); # for loading some data ;)

$plugin_data{$PLUGIN_NAME}->{inmessage_h}=\&EraOmnix_Plat_InMessage;
$plugin_data{$PLUGIN_NAME}->{will_take_h}=\&EraOmnix_Plat_WillTake;
$plugin_data{$PLUGIN_NAME}->{default_prio}=$DEFAULT_PRIO;
$plugin_data{$PLUGIN_NAME}->{version}=$PLUGIN_VERSION;
$plugin_data{$PLUGIN_NAME}->{needs_reg}=1;

sub EraOmnix_Plat_WillTake {
        my $from=shift;
        my $to_nr=shift; # if not provided, it means it asks for the service, w/o number served by it 
        return (($to_nr?($to_nr =~ /$DEST_NUMBERS_REGEXP/):1)&&(exists($EraOmnix_Plat_accounts{$from})));
};

sub EraOmnix_Plat_PreConn {
#	%EraOmnix_Plat_accounts=%{LoadXMLHash('accounts',$config{plugins}->{$PLUGIN_NAME}->{accounts_file},$PLUGIN_NAME)};
	my $t=tie(%EraOmnix_Plat_accounts,"MLDBM::Sync",$config{plugins}->{$PLUGIN_NAME}->{accounts_file},O_CREAT|O_RDWR,0600);
	log2($PLUGIN_NAME.": Ready.");
};

sub EraOmnix_Plat_InIQ {
	my $iq_o=shift;
	my $xmlns=shift;
	my $query_o=$iq_o->GetQuery();
	my $type=$iq_o->GetType();
	my $from=$iq_o->GetFrom(); my $to=$iq_o->GetTo();
	my $iq=new Net::Jabber::IQ;
	$iq->SetFrom($to); $iq->SetTo($from); $iq->SetID($iq_o->GetID);
	my $query=$iq->NewQuery($xmlns);

	if ($xmlns eq 'jabber:iq:register') {
		my $base_from=$from; $base_from=~s/\/.+$//g if ($base_from =~ /\//);
		my $account=$EraOmnix_Plat_accounts{$base_from};
		if ($type eq 'get') {
			$iq->SetType('result');
			$query->SetInstructions('Send a message to: +48TELNUMBER@'.$config{service_name}." to send an SMS.\n".
				"You can add a contact like this to your roster.\n\n".
				"Provide your Username and Password to ".$PLUGIN_NAME." gateway.\n".
				"See http://www.eraomnix.pl/sms/super/ for info.\n\n".
				"Note: x:data compilant client allows setting more options.");
			$query->SetUsername( ($account?$account->{username}:'') );
			$query->SetPassword('');
			# x:data ...
			my $xd=( (Net::Jabber->VERSION>1.30) ? new Net::Jabber::Stanza("x") : new Net::Jabber::X );
			$xd->SetXMLNS('jabber:x:data');
			$xd->SetData(instructions=>'Send a message to: +48TELNUMBER@'.$config{service_name}." to send an SMS.\n".
					"You can add a contact like this to your roster.\n".
					"Provide your Username and Password to ".$PLUGIN_NAME." gateway.\n".
					"See http://www.eraomnix.pl/sms for info.\n".
					"You can configure additional options too. When changing options, remember to provide ".
					"your password!",
				title=>'EraOmnix_Platna Registration',
				type=>'form');
			$xd->AddField(type=>'text-single',var=>'username',label=>'User name',
				value=>($account?$account->{username}:''));
			$xd->AddField(type=>'text-private',var=>'password',label=>'Password (!) ');
			$xd->AddField(type=>'text-single',var=>'contact',label=>'Return contact',
				value=>($account?$account->{contact}:''));
			$xd->AddField(type=>'text-single',var=>'signature',label=>'Signature',
				value=>($account?$account->{signature}:''));
			$xd->AddField(type=>'boolean',var=>'smartBreaking',label=>'Avoid word-breaking',
				value=>($account->{smartBreaking}?$account->{smartBreaking}:0));
			$xd->AddField(type=>'boolean',var=>'alert',label=>'Alert mode',
				value=>($account->{alert}?$account->{alert}:0));
			$xd->AddField(type=>'boolean',var=>'ems',label=>'EMS',
				value=>($account->{ems}?$account->{ems}:0));
			$xd->AddField(type=>'boolean',var=>'status',label=>'Status to e-mail',
				value=>($account->{status}?$account->{status}:0));
			$query->AddX($xd);
			# ... x:data
			$Connection->Send($iq);
		} elsif ($type eq 'set') {
			# x:data ...
			my @xd=$query_o->GetX('jabber:x:data'); my %f;
			if ($#xd>-1) {
				foreach my $x ($xd[0]->GetFields()) { $f{$x->GetVar()}=$x->GetValue(); };
			} else {
				$f{username}=$query_o->GetUsername(); $f{password}=$query_o->GetPassword();
				$f{contact}=''; $f{signature}=$base_from; $f{signature}=~s/@.+$//g;
				$f{smartBreaking}=0; $f{alert}=0; $f{ems}=0; $f{status}=0;
			};
			# ... x:data
			if (($f{username} eq '')&&($f{password} eq '')) {
				SendPluginPresencesToUser($PLUGIN_NAME,'unavailable',$from);
				delete $EraOmnix_Plat_accounts{$base_from};
			} else {
				for my $i (qw(username password contact signature smartBreaking alert ems status)) { $account->{$i}=$f{$i}; };
				$EraOmnix_Plat_accounts{$base_from}=$account;
				SendPluginPresencesToUser($PLUGIN_NAME,'available',$from);
				PushAgentToUsersRoster($from); # important in any plugin which needs registration!
			};
#			SaveXMLHash(\%EraOmnix_Plat_accounts,'accounts',$config{plugins}->{$PLUGIN_NAME}->{accounts_file},$PLUGIN_NAME);
			$iq->SetType('result');
			$Connection->Send($iq);
		};
	};
};

my %EraOmnix_Plat_errmsgs=(
	'0'=>'wysy�ka bez b��du',
	'1'=>'awaria systemu',
	'2'=>'u�ytkownik nieautoryzowany',
	'3'=>'dost�p zablokowany',
	'5'=>'b��d sk�adni',	
	'7'=>'wyczerpany limit SMS',
	'8'=>'b��dny adres odbiorcy SMS',
	'9'=>'wiadomo�� zbyt d�uga',
	'10'=>'brak wymaganej liczby �eton�w'
);

sub EraOmnix_Plat_InMessage {
	my $message_o=shift;
	my $type=shift;
	my $to=$message_o->GetTo(); my $from=$message_o->GetFrom();
	my $message=new Net::Jabber::Message;
	$message->SetTo($from); $message->SetFrom($to); $message->SetType($type);
	my $SN=$config{service_name};
	my $PN=$SN."/".$PLUGIN_NAME;
	my $base_from=$from; $base_from=~s/\/.+$//g if ($base_from =~ /\//);
	my $nr=$to; $nr=~s/@.+$//g;
	return unless ($to =~ /$PN$/); # shouldn't happen

	my $account=$EraOmnix_Plat_accounts{$base_from};

	# the guts:

	my $result_message="";
	$nr=~s/\+//g;
	my $sig=$base_from; $sig=~s/@.+$//g;

	my $ua=new LWP::UserAgent;
	$ua->agent("Mozilla/3.0 (X11, I, Linux 2.4.0 i486"); # ;)
	$ua->timeout(30); # quickly please!
	$ua->no_proxy('www.eraomnix.pl');

	my $r=$ua->post('http://www.eraomnix.pl/sms/do/extern/tinker/super/send',[
		login=>$account->{username},
		password=>$account->{password},
		success=>'http://success/',
		failure=>'http://failure/',
		numbers=>$nr,
		message=>convert('utf8','latin2',$message_o->GetBody()),
		signature=>( $account->{signature} ? $account->{signature} : $sig),
		contact=>( $account->{contact} ? $account->{contact} : ""),
		smartBreaking=>( ($account->{smartBreaking} =~ /(true|yes|1)/) ? "on" : "off" ),
		ems=>( ($account->{ems} =~ /(true|yes|1)/) ? "on" : "off" ),
		alert=>( ($account->{alert} =~ /(true|yes|1)/) ? "on" : "off" ),
		status=>( ($account->{status} =~ /(true|yes|1)/) ? "on" : "off" ),
		]);
	if ($r->status_line =~ /302 Moved/) {
		my $loc=$r->header("Location");
		if ($loc =~ /\/success\//) {
			my $err=($loc =~ /X-ERA-error/)?$loc:""; $err=~s/^.+X-ERA-error=//g; $err=~s/\&.+$//g;
			my $tok=($loc =~ /X-ERA-tokens/)?$loc:""; $tok=~s/^.+X-ERA-tokens=//g; $tok=~s/\&.+$//g;
			my $cost=($loc =~ /X-ERA-cost/)?$loc:""; $cost=~s/^.+X-ERA-cost=//g; $cost=~s/\&.+$//g;
			$result_message=convert('latin2','utf8',"SMS wys�any".
				(($err ne '')?", status: ".$EraOmnix_Plat_errmsgs{$err}:"").
				(($tok ne '')?", pozosta�o token�w: $tok":"").
				(($cost ne '')?", zu�yte tokeny: $cost":""));
		} else {
			my $err=($loc =~ /X-ERA-error/)?$loc:""; $err=~s/^.+X-ERA-error=//g; $err=~s/\&.+$//g;
			my $tok=($loc =~ /X-ERA-tokens/)?$loc:""; $tok=~s/^.+X-ERA-tokens=//g; $tok=~s/\&.+$//g;
			my $cost=($loc =~ /X-ERA-cost/)?$loc:""; $cost=~s/^.+X-ERA-cost=//g; $cost=~s/\&.+$//g;
			$result_message=convert('latin2','utf8',"B��d wysy�ania".
				(($err ne '')?", status: ".$EraOmnix_Plat_errmsgs{$err}:"").
				(($tok ne '')?", pozosta�o token�w: $tok":"").
				(($cost ne '')?", zu�yte tokeny: $cost":""));
		};
	} else {
		$result_message="HTTP Error";
	};

	$message->SetBody("www.eraomnix.pl: ".$result_message);
	$Connection->Send($message);
};

1;

