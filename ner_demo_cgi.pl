#!/usr/bin/perl

use strict;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use File::Basename;
use IO::Socket;
use  List::Util;

# $CGI::POST_MAX = 1024 * 5000;
my $safe_filename_characters = "a-zA-Z0-9_.-";

my $query = new CGI;
my $host = 'xxx.xxx.xxx.xxx';
my $port = '6666';
my $xml_data = $query->param ("xml_data");

$host =~ /^(?:\d{1,3}\.){3}\d{1,3}$/m or show_err_msg ("IP is NOT legal.");
$port =~ /^\d+$/m or show_err_msg ("PORT is NOT legal.");


my $remote = IO::Socket::INET->new (Proto  => "tcp",
                                 PeerAddr => $host,
                                 PeerPort => $port)
or show_err_msg ("Couldn't connect to $host:$port\n$!\n$@\n");

my ($send_header, $proc_data) = wrap ($xml_data);
$remote->send ($send_header) or show_err_msg ("Couldn't send: $!\n$@\n");
$remote->send ($proc_data) or show_err_msg ("Couldn't send: $!\n$@\n");

my $answer = <$remote> || '---';
my @nre_names = unwrap ($answer);

print $query->header (-charset => 'gb2312', -type => 'text/html');

print '<p><br />', $xml_data, '</p><p>have the names recognized as below:</p><br />' if 0 + @nre_names;

for (@nre_names) {
  print '<button type="button">', $_, '</button>';
}


close $remote;

exit (0);

sub wrap {
	my ($raw_str) = @_;
	my $header = pack ("a8i", 'NER_iSRV', 1 + length $raw_str);

	return ($header, $raw_str."\n"); 
}

sub unwrap {
	my ($packet) = @_;
	my ($checksum, $all_len, $names_str) = unpack "a8ia*", $packet;

	$checksum eq 'NER_iSRV' or show_err_msg ("return protocal error");
	$all_len > 0 or show_err_msg ("return proc error: $all_len");
	length $names_str != $all_len + 1 or show_err_msg ("return $names_str $all_len length.");
	
	chomp $names_str;

	return split /\+/, $names_str;
}

sub show_err_msg {
	print $query->header (-charset => 'gb2312', -type => 'text/html');
	print "<button onclick=\"location.href='/ner_demo.html\'\">return<\/button>";

	my ($msg) = @_;
	die "$msg";
}

__END__

# html


<html>
	<head>
		<meta http-equiv="Content-Type" content="text/html; charset=gb2312" />
		<title>NER tool online demo</title>
		<link type="text/css" rel="stylesheet" href="/tooltip/themes/1/tooltip.css" />
		<script type="text/javascript" src="/tooltip/themes/1/tooltip.js"></script>
	</head>
	<body>
		<h1>The NER tool online demo.</h1>
		<form action="/cgi-bin/ner_online_demo.pl" method="post" enctype="multipart/form-data">
			<p><br>feed string to ner tool: <br><textarea name="xml_data" rows="10" cols="60"  onmouseover="tooltip.pop(this, '<h3>用前必读：</h3>所有识别的名字都是现阶段视频处理的数据中抽出的，支持转义字符和多语言。<h4>注意：</h4>不支持未登录名')">大S听周杰说周杰伦信不信方中信说的话取决于5月天成员信的行动！！林原めぐみchar6mingこおろぎさとみ88888こおろぎさとみ   浪川大辅</textarea></p>
			<br>
			<p><input type="submit" name="Submit" value="submit" />&#9;<input type="reset"></p>
		</form>
	</body>
</html>
