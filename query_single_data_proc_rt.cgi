#!/usr/bin/perl

use strict;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use File::Basename;
use IO::Socket;

# $CGI::POST_MAX = 1024 * 5000;
my $safe_filename_characters = "a-zA-Z0-9_.-";

my $query = new CGI;
my $host = $query->param ("ip");
my $port = $query->param ("port");
my $filename = $query->param ("photo");
my $xml_data = $query->param ("xml_data");

my $upload_filehandle = $query->upload ("photo");

$host =~ /^(?:\d{1,3}\.){3}\d{1,3}$/m or show_err_msg ("IP is NOT legal.");
$port =~ /^\d+$/m or show_err_msg ("PORT is NOT legal.");

# Forbid anyone to access the online host ^_^
'xxx.xxx.xxx.xxxx' eq $host and show_err_msg ("Forbid anyone to access the online host ^_^");

my $img_data = '';

if (defined $filename and length $filename > 0) {
	my ($name, $path, $extension) = fileparse ($filename, '..*');
	$filename = $name . $extension;
	$filename =~ tr/ /_/;
	$filename =~ s/[^$safe_filename_characters]//g;

	if ($filename =~ /^([$safe_filename_characters]+)$/) {
		$filename = $1;
	} else {
		show_err_msg ("Filename $filename contains invalid characters");
	}

	$img_data .= $_ while (<$upload_filehandle>);
}

my $remote = IO::Socket::INET->new (Proto  => "tcp",
                                 PeerAddr => $host,
                                 PeerPort => $port)
or show_err_msg ("Couldn't connect to $host:$port\n$!\n$@\n");

my ($send_header, $proc_data) = wrap ($xml_data, $img_data, $filename);
$remote->send ($send_header) or show_err_msg ("Couldn't send: $!\n$@\n");
$remote->send ($proc_data) or show_err_msg ("Couldn't send: $!\n$@\n");

my $answer = <$remote> || '---';
my $response = unwrap ($answer);

print $query->header (-charset => 'gb2312', -type => 'text/plain');

if ($response =~ m/^</) {
  print "$response\n";
} else {
	my $v_start = -1;
	while ($response = <$remote>) {
		$v_start = index $response, '<video>';
		last if -1 != $v_start;
	}
	print substr $response, $v_start;
}

print "$_" while (<$remote>);

close $remote;

exit;

sub wrap {
	my ($xml, $img, $img_name) = @_;
	my $xml_len = length $xml;
	my $img_len = length $img;
	my $img_name_len = length $img_name;
	my ($header, $send_data) = ();
	my $img_sum = 0;
	defined $img and defined $img_name and $img_len > 0 and $img_name_len > 0 and $img_sum = 1;
	$header = pack ("a8i", 'XXXXXX.0', 30 + $xml_len + (1 == $img_sum ? $img_len + $img_name_len + 8: 0));
	if (1 == $img_sum) {
	  $send_data = pack ("sa16ss i a$xml_len i ia$img_name_len i a$img_len", 1, '', 6, 0, $xml_len, $xml, 1, $img_name_len, $img_name, $img_len, $img);
	} else {
	  $send_data = pack ("sa16ss i a$xml_len i", 1, '', 6, 0, $xml_len, $xml, 0);
	}
	
	return ($header, $send_data); 
}

sub unwrap {
	my ($packet) = @_;
	my ($checksum, $all_len, $moule, $save, $rt_val, $cmd, $rt_xml_len, $video_start) = unpack "a8isa12isiA*", $packet;

	$checksum eq 'XXXXXX.0' or show_err_msg ("return protocal error");
#	$all_len >= 20 or show_err_msg ("return len error: $all_len");
#	1 == $moule or show_err_msg ("return error code: not proc return data.");
	0 == $rt_val or show_err_msg ("return error code: proc errcode $rt_val.");
#	6 == $cmd or show_err_msg ("return error code: return cmd $cmd.");

	return $video_start;
}

sub show_err_msg {
	print $query->header (-charset => 'gb2312', -type => 'text/html');
	print "<button onclick=\"location.href='/c_proc_result.html\'\">return<\/button>";

	my ($msg) = @_;
	die "$msg";
}

__END__

# html

<html>
	<head>
		<meta http-equiv="Content-Type" content="text/html; charset=gb2312" />
		<title>proccess tools</title>
		<link type="text/css" rel="stylesheet" href="/tooltip/themes/1/tooltip.css" />
		<script type="text/javascript" src="/tooltip/themes/1/tooltip.js"></script>
	</head>
	<body>
		<h1>You can test single xml data to see it's reslut.</h1>
		<form action="/cgi-bin/query_proc_result.pl" method="post" enctype="multipart/form-data">
			<p>&nbsp;ip&nbsp;: <input type="text" name="ip"  onmouseover="tooltip.pop(this, '<h3>IP / PORT 对应哪套系统？</h3>xxx.xxx.xxx.xxx:xxxx是测试系统</br> xxx.xxx.xxx.xxx:xxxx是测试系统2</br><h4>注意：</h4>不要企图使用线上的系统测试数据，我已经把IP过滤了 ^_^')" ></p>
			<p>port: <input type="text" name="port" onmouseover="tooltip.pop(this, ''<h3>IP / PORT 对应哪套系统？</h3>xxx.xxx.xxx.xxx:xxxx是测试系统</br> xxx.xxx.xxx.xxx:xxxx是测试系统2</br><h4>注意：</h4>不要企图使用线上的系统测试数据，我已经把IP过滤了 ^_^')" ></p>
			<p><br>want to proc xml: <br><textarea name="xml_data" rows="20" cols="80"  onmouseover="tooltip.pop(this, '<h3>用前必读，否则我保证你输入的数据处理不了：</h3>为了方便调试，上面数据1；下面是数据2。切记每次只能输入一个数据。为了调试数据的某个字段你可以删除一个数据，在剩下的一条数据的基础上修改字段。或者用xxx的工具查询采集的原始数据，过滤掉一些非法字符（我一般只用一条正则表达式s#>\s+?<#><\#处理）后，copy到这里测试。另外需要注意的是：图片数据如果没有，src_data字段的data删除，或者选择上传本地的小图片，但别忘记src_data字段的data就是本地上传图片的文件名。<h4>注意：</h4>如果提供错误数据，处理失败会输出一个query_proc_result.pl文件，下载到本地')">

				</textarea></p>
			<p>src data img upload: <input type="file" name="photo"  onmouseover="tooltip.pop(this, 'Note: MUST modify the *data* value if you choose upload a picture.')" /></p><br>
			<p><input type="submit" name="Submit" value="submit" />&#9;<input type="reset"></p>
		</form>
	</body>
</html>
