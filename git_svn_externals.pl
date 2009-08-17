#!/usr/bin/perl

#
# git_svn_externals.pl
#
# Author:
#  Dmitry Sushko <Dmitry.Sushko@yahoo.com>
#

use strict;
use warnings;
use Cwd;
use File::Path;
use File::Basename;

my $git_executable         = "git";
my $git_directory          = ".git";
my $git_externals_dir      = ".git_externals";
my $show_externals_command = "$git_executable svn show-externals";
my $clone_external_command = "$git_executable svn clone";
my $git_svn_pull_command   = "$git_executable svn fetch && $git_executable svn rebase";
my $git_svn_fetch_command  = "$git_executable svn fetch";
my $git_svn_rebase_command = "$git_executable svn rebase";

sub IsGitRepository {
	if (-d $git_directory) {
		return 1;
	} else {
		return 0;
	}
}

sub GitSvnCloneExternal {
	my ($ext_path, $ext_url, $ext_rev) = @_;
	$ext_rev ||= "";

	my $ext_basename = basename($ext_path);
	my $ext_dirname  = dirname($ext_path);

	print "DBG: Dirname = [$ext_dirname], Basename = [$ext_basename]\n";

	mkpath $ext_dirname unless -d $ext_dirname;

	mkpath $git_externals_dir unless -d $git_externals_dir;

	my $ext_full_dirname = join ("/", $git_externals_dir, $ext_dirname);
	mkpath $ext_full_dirname unless -d $ext_full_dirname;

	my $tmp_current_working_dir = cwd();

	chdir $git_externals_dir . "/" . $ext_dirname;
	unless (-d $ext_basename) {
		print "NFO: External directory doesn't exist\n";
		# external directory doesn't exist
		if ($ext_rev =~ m/^$/) {
			qx/$clone_external_command $ext_url $ext_basename/;
		} else {
			qx/$clone_external_command $ext_rev $ext_url $ext_basename/;
		}
	} else {
		print "NFO: External directory exists\n";
		# directory already exists
		my $tmp_wd = cwd();
		chdir $ext_basename;
		my $is_git_repo = &IsGitRepository;
		if (1 == $is_git_repo) {
			print "NFO: External already cloned, updating\n";
			if ($ext_rev =~ m/^$/) {
				qx/$git_svn_pull_command/;
			} else {
				qx/$git_svn_pull_command/;
				# now find the git commit sha of the interesting revision
				my $git_svn_rev = $ext_rev;
				$git_svn_rev =~ s/(-|\s)//g;
				print "DBG: git_svn_rev = $git_svn_rev\n";
				my $git_sha = qx/git svn find-rev $git_svn_rev/;
				$git_sha =~ s/\n//;
				print "DBG: found git sha: $git_sha\n";
				qx/$git_executable checkout master/;
				qx/$git_executable branch -f __git_ext_br $git_sha/;
				qx/$git_executable checkout __git_ext_br/;
			}
			chdir $tmp_wd;
		} else {
			chdir $tmp_wd;
			if ($ext_rev =~ m/^$/) {
				qx/$clone_external_command $ext_url $ext_basename/;
			} else {
				qx/$clone_external_command $ext_rev $ext_url $ext_basename/;
			}
		}
	}

	my $tmp_ext_dir = $tmp_current_working_dir . "/" . $ext_dirname;
	print "DBG: tmp_ext_dir = $tmp_ext_dir\n";
	chdir $tmp_ext_dir;
	my $git_repo_root_dir = qx/git rev-parse --show-cdup/;
	$git_repo_root_dir =~ s/\n$//;
	my $link_to_dir = $git_repo_root_dir . $git_externals_dir . "/" . $ext_path;
	print "DBG: Linking $link_to_dir -> $ext_basename\n";
	qx/ln -snf $link_to_dir $ext_basename/;

	# exclude external from current git
	chdir $tmp_current_working_dir;

	# Populate hash with possible excludes
	my %pending_excludes = ( $git_externals_dir => 1, $ext_path => 1 );

	open FILE, "<", ".git/info/exclude";
	while (my $line = <FILE>) {
		if ($line =~ m/^$git_externals_dir\n$/) {
			delete $pending_excludes{$git_externals_dir};
		}
		if ($line =~ m/^$ext_path\n$/) {
			delete $pending_excludes{$ext_path};
		}
	}
	close FILE;

	open (GITEXCLUDE, ">>.git/info/exclude") or die "Error: $!\n";
	for my $exclude (keys %pending_excludes) {
		print GITEXCLUDE "$exclude\n";
	}
	close GITEXCLUDE;

	# recursive check for externals
	chdir $tmp_current_working_dir."/".$git_externals_dir."/".$ext_dirname."/".$ext_basename;
	&ListGitSvnExternals();

	chdir $tmp_current_working_dir;
}

sub ListGitSvnExternals {
	my @show_externals_output = qx/$show_externals_command/;
	my $line;
	my @externals;
	foreach $line (@show_externals_output) {
		$line =~ s/\n$//;
		if ($line =~ m/^# \//) {
			next;
		} elsif ($line =~ m/^$/) {
			next;
		} else {
			#print "NFO: Found external: $line\n";
			push(@externals, $line);
		}
	}

	my @external_hashes;
	my $external;
	my $ext_path;
	my $ext_rev;
	my $ext_url;
	foreach $external (@externals) {
		if ($external =~ m/(.+)\s(-r\s\S+)\s((file:|http:|https:|svn:|svn\+ssh:)\S+)/) {
			# found an external with revision specified
			$ext_path = $1;
			$ext_rev  = $2;
			$ext_url  = $3;
			$ext_path =~ s/\///;
			print "NFO: External found:\n" .
			    "   path: $ext_path\n" .
			    "   rev : $ext_rev\n" .
			    "   url : $ext_url\n";
			&GitSvnCloneExternal ($ext_path, $ext_url, $ext_rev);
		} elsif ($external =~ m/(.+)\s((file:|http:|https:|svn:|svn\+ssh:)\S+)/) {
			# found an external without revision specified
			$ext_path = $1;
			$ext_url  = $2;
			$ext_path =~ s/\///;
			print "NFO: External found:\n" .
			    "   path: $ext_path\n" .
			    "   url : $ext_url\n";
			&GitSvnCloneExternal ($ext_path, $ext_url);
		} else {
			print "ERR: Malformed external specified: $external\n";
			next;
		}
	}
}

&ListGitSvnExternals();