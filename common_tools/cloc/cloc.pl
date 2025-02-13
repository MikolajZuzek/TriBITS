#!/usr/bin/env perl
# cloc -- Count Lines of Code {{{1
# Copyright (C) 2006-2011 Northrop Grumman Corporation
# Author:  Al Danial <al.danial@gmail.com>
#          First release August 2006
#
# Includes code from:
#   - SLOCCount v2.26 
#     http://www.dwheeler.com/sloccount/
#     by David Wheeler.
#   - Regexp::Common v2.120
#     http://search.cpan.org/~abigail/Regexp-Common-2.120/lib/Regexp/Common.pm
#     by Damian Conway and Abigail.
#   - Win32::Autoglob 
#     http://search.cpan.org/~sburke/Win32-Autoglob-1.01/Autoglob.pm
#     by Sean M. Burke.
#   - Algorithm::Diff
#     http://search.cpan.org/~tyemq/Algorithm-Diff-1.1902/lib/Algorithm/Diff.pm
#     by Tye McQueen.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details:
# http://www.gnu.org/licenses/gpl.txt
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
# 1}}}
my $VERSION = sprintf("%.2f", 1.55);
my $URL     = "http://cloc.sourceforge.net";
require 5.006;
# use modules                                  {{{1
use warnings;
use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw { tempfile tempdir };
use File::Find;
use File::Path;
use File::Spec;
use IO::File;
use POSIX "strftime";

# Digest::MD5 isn't in the standard distribution. Use it only if installed.
my $HAVE_Digest_MD5 = 0;
eval "use Digest::MD5;";
if (defined $Digest::MD5::VERSION) {
    $HAVE_Digest_MD5 = 1;
} else {
    warn "Digest::MD5 not installed; will skip file uniqueness checks.\n";
}

my $HAVE_Rexexp_Common;
# Regexp::Common isn't in the standard distribution.  It will
# be installed in a temp directory if necessary.
BEGIN {
    if (eval "use Regexp::Common;") {
        $HAVE_Rexexp_Common = 1;
    } else {
        $HAVE_Rexexp_Common = 0;
    }
}

my $HAVE_Algorith_Diff = 0;
# Algorithm::Diff isn't in the standard distribution.  It will
# be installed in a temp directory if necessary.
eval "use Algorithm::Diff qw ( sdiff ) ";
if (defined $Algorithm::Diff::VERSION) {
    $HAVE_Algorith_Diff = 1;
} else {
    Install_Algorithm_Diff();
}
# print "2 HAVE_Algorith_Diff = $HAVE_Algorith_Diff\n";
# test_alg_diff($ARGV[$#ARGV - 1], $ARGV[$#ARGV]); die;

# Uncomment next two lines when building Windows executable with perl2exe
# or if running on a system that already has Regexp::Common.
#use Regexp::Common;
#$HAVE_Rexexp_Common = 1;

#perl2exe_include "Regexp/Common/whitespace.pm"
#perl2exe_include "Regexp/Common/URI.pm"
#perl2exe_include "Regexp/Common/URI/fax.pm"
#perl2exe_include "Regexp/Common/URI/file.pm"
#perl2exe_include "Regexp/Common/URI/ftp.pm"
#perl2exe_include "Regexp/Common/URI/gopher.pm"
#perl2exe_include "Regexp/Common/URI/http.pm"
#perl2exe_include "Regexp/Common/URI/pop.pm"
#perl2exe_include "Regexp/Common/URI/prospero.pm"
#perl2exe_include "Regexp/Common/URI/news.pm"
#perl2exe_include "Regexp/Common/URI/tel.pm"
#perl2exe_include "Regexp/Common/URI/telnet.pm"
#perl2exe_include "Regexp/Common/URI/tv.pm"
#perl2exe_include "Regexp/Common/URI/wais.pm"
#perl2exe_include "Regexp/Common/CC.pm"
#perl2exe_include "Regexp/Common/SEN.pm"
#perl2exe_include "Regexp/Common/number.pm"
#perl2exe_include "Regexp/Common/delimited.pm"
#perl2exe_include "Regexp/Common/profanity.pm"
#perl2exe_include "Regexp/Common/net.pm"
#perl2exe_include "Regexp/Common/zip.pm"
#perl2exe_include "Regexp/Common/comment.pm"
#perl2exe_include "Regexp/Common/balanced.pm"
#perl2exe_include "Regexp/Common/lingua.pm"
#perl2exe_include "Regexp/Common/list.pm"
#perl2exe_include "File/Glob.pm"

use Text::Tabs qw { expand };
use Cwd qw { cwd };
# 1}}}
# Usage information, options processing.       {{{1
my $ON_WINDOWS = 0;
   $ON_WINDOWS = 1 if ($^O =~ /^MSWin/) or ($^O eq "Windows_NT");
if ($ON_WINDOWS and $ENV{'SHELL'}) {
    if ($ENV{'SHELL'} =~ m{^/}) {
        $ON_WINDOWS = 1;  # make Cygwin look like Unix
    } else {
        $ON_WINDOWS = 0;  # MKS defines $SHELL but still acts like Windows
    }
}

my $NN     = chr(27) . "[0m";  # normal
   $NN     = "" if $ON_WINDOWS;
my $BB     = chr(27) . "[1m";  # bold
   $BB     = "" if $ON_WINDOWS;
my $script = basename $0;
my $usage  = "
Usage: $script [options] <file(s)/dir(s)> | <set 1> <set 2> | <report files>

 Count, or compute differences of, physical lines of source code in the 
 given files (may be archives such as compressed tarballs or zip files) 
 and/or recursively below the given directories.

 ${BB}Input Options${NN}
   --extract-with=<cmd>      This option is only needed if cloc is unable
                             to figure out how to extract the contents of
                             the input file(s) by itself.
                             Use <cmd> to extract binary archive files (e.g.:
                             .tar.gz, .zip, .Z).  Use the literal '>FILE<' as 
                             a stand-in for the actual file(s) to be
                             extracted.  For example, to count lines of code
                             in the input files 
                                gcc-4.2.tar.gz  perl-5.8.8.tar.gz  
                             on Unix use  
                               --extract-with='gzip -dc >FILE< | tar xf -'
                             or, if you have GNU tar,
                               --extract-with='tar zxf >FILE<' 
                             and on Windows use: 
                               --extract-with=\"\\\"c:\\Program Files\\WinZip\\WinZip32.exe\\\" -e -o >FILE< .\"
                             (if WinZip is installed there).
   --list-file=<file>        Take the list of file and/or directory names to 
                             process from <file> which has one file/directory 
                             name per line.  See also --exclude-list-file.
   --unicode                 Check binary files to see if they contain Unicode
                             expanded ASCII text.  This causes performance to
                             drop noticeably.

 ${BB}Processing Options${NN}
   --autoconf                Count .in files (as processed by GNU autoconf) of 
                             recognized languages.
   --by-file                 Report results for every source file encountered.
   --by-file-by-lang         Report results for every source file encountered
                             in addition to reporting by language.
   --diff <set1> <set2>      Compute differences in code and comments between
                             source file(s) of <set1> and <set2>.  The inputs
                             may be pairs of files, directories, or archives.
                             Use --diff-alignment to generate a list showing
                             which file pairs where compared.  See also
                             --ignore-case, --ignore-whitespace.
   --follow-links            [Unix only] Follow symbolic links to directories
                             (sym links to files are always followed).
   --force-lang=<lang>[,<ext>]
                             Process all files that have a <ext> extension 
                             with the counter for language <lang>.  For 
                             example, to count all .f files with the 
                             Fortran 90 counter (which expects files to 
                             end with .f90) instead of the default Fortran 77 
                             counter, use
                               --force-lang=\"Fortran 90\",f
                             If <ext> is omitted, every file will be counted
                             with the <lang> counter.  This option can be 
                             specified multiple times (but that is only
                             useful when <ext> is given each time).  
                             See also --script-lang, --lang-no-ext.
   --ignore-whitespace       Ignore horizontal white space when comparing files
                             with --diff.  See also --ignore-case.
   --ignore-case             Ignore changes in case; consider upper- and lower-
                             case letters equivalent when comparing files with
                             --diff.  See also --ignore-whitespace.
   --lang-no-ext=<lang>      Count files without extensions using the <lang> 
                             counter.  This option overrides internal logic 
                             for files without extensions (where such files 
                             are checked against known scripting languages
                             by examining the first line for #!).  See also 
                             --force-lang, --script-lang.
   --read-binary-files       Process binary files in addition to text files.
                             This is usually a bad idea and should only be
                             attempted with text files that have embedded 
                             binary data.
   --read-lang-def=<file>    Load from <file> the language processing filters.
                             (see also --write-lang-def) then use these filters
                             instead of the built-in filters.
   --script-lang=<lang>,<s>  Process all files that invoke <s> as a #!
                             scripting language with the counter for language
                             <lang>.  For example, files that begin with
                                #!/usr/local/bin/perl5.8.8
                             will be counted with the Perl counter by using
                                --script-lang=Perl,perl5.8.8
                             The language name is case insensitive but the
                             name of the script language executable, <s>,
                             must have the right case.  This option can be 
                             specified multiple times.  See also --force-lang,
                             --lang-no-ext.
   --sdir=<dir>              Use <dir> as the scratch directory instead of
                             letting File::Temp chose the location.  Files
                             written to this location are not removed at
                             the end of the run (as they are with File::Temp).
   --skip-uniqueness         Skip the file uniqueness check.  This will give
                             a performance boost at the expense of counting
                             files with identical contents multiple times
                             (if such duplicates exist).
   --strip-comments=<ext>    For each file processed, write to the current
                             directory a version of the file which has blank
                             lines and comments removed.  The name of each
                             stripped file is the original file name with 
                             .<ext> appended to it.  It is written to the
                             current directory unless --original-dir is on.
   --original-dir            [Only effective in combination with 
                             --strip-comments]  Write the stripped files 
                             to the same directory as the original files.
   --sum-reports             Input arguments are report files previously
                             created with the --report-file option.  Makes
                             a cumulative set of results containing the
                             sum of data from the individual report files.

 ${BB}Filter Options${NN}
   --exclude-dir=<D1>[,D2,]  Exclude the given comma separated directories
                             D1, D2, D3, et cetera, from being scanned.  For
                             example  --exclude-dir=.cache,test  will skip
                             all files that have /.cache/ or /test/ as part
                             of their path.
                             Directories named .cvs and .svn are always
                             excluded.
   --exclude-ext=<ext1>[,<ext2>[...]]
                             Do not count files having the given file name 
                             extensions.
   --exclude-lang=<L1>[,L2,] Exclude the given comma separated languages
                             L1, L2, L3, et cetera, from being counted.
   --exclude-list-file=<file>  Ignore files and/or directories whose names 
                             appear in <file>.  <file> should have one entry 
                             per line.  Relative path names will be resolved 
                             starting from the directory where cloc is 
                             invoked.  See also --list-file.
   --match-f=<regex>         Only count files whose basenames match the Perl 
                             regex.  For example
                               --match-f=^[Ww]idget
                             only counts files that start with Widget or widget.
   --not-match-f=<regex>     Count all files except those whose basenames
                             match the Perl regex.
   --match-d=<regex>         Only count files in directories matching the Perl 
                             regex.  For example
                               --match-d=/src/
                             only counts files in directories containing
                             /src/
   --not-match-d=<regex>     Count all files except those in directories
                             matching the Perl regex.
   --skip-win-hidden         On Windows, ignore hidden files.

 ${BB}Debug Options${NN}
   --categorized=<file>      Save names of categorized files to <file>.
   --counted=<file>          Save names of processed source files to <file>.
   --diff-alignment=<file>   Write to <file> a list of files and file pairs 
                             showing which files were added, removed, and/or
                             compared during a run with --diff.  This switch
                             forces the --diff mode on.
   --help                    Print this usage information and exit.
   --found=<file>            Save names of every file found to <file>.
   --ignored=<file>          Save names of ignored files and the reason they
                             were ignored to <file>.
   --print-filter-stages     Print to STDOUT processed source code before and 
                             after each filter is applied.
   --show-ext[=<ext>]        Print information about all known (or just the
                             given) file extensions and exit.
   --show-lang[=<lang>]      Print information about all known (or just the
                             given) languages and exit.
   -v[=<n>]                  Verbose switch (optional numeric value).
   --version                 Print the version of this program and exit.

   --write-lang-def=<file>   Writes to <file> the language processing filters
                             then exits.  Useful as a first step to creating
                             custom language definitions (see --read-lang-def).

 ${BB}Output Options${NN}
   --3                       Print third-generation language output.
                             (This option can cause report summation to fail
                             if some reports were produced with this option
                             while others were produced without it.)
   --progress-rate=<n>       Show progress update after every <n> files are
                             processed (default <n>=100).  Set <n> to 0 to
                             suppress progress output (useful when redirecting
                             output to STDOUT).
   --quiet                   Suppress all information messages except for
                             the final report.
   --report-file=<file>      Write the results to <file> instead of STDOUT.
   --out=<file>              Synonym for --report-file=<file>.
   --csv                     Write the results as comma separated values.
   --sql=<file>              Write results as SQL create and insert statements
                             which can be read by a database program such as
                             SQLite.  If <file> is 1, output is sent to STDOUT.
   --sql-project=<name>      Use <name> as the project identifier for the 
                             current run.  Only valid with the --sql option.
   --sql-append              Append SQL insert statements to the file specified
                             by --sql and do not generate table creation 
                             statements.  Only valid with the --sql option.
   --sum-one                 For plain text reports, show the SUM: output line 
                             even if only one input file is processed.
   --xml                     Write the results in XML.
   --xsl=<file>              Reference <file> as an XSL stylesheet within
                             the XML output.  If <file> is 1 (numeric one), 
                             writes a default stylesheet, cloc.xsl (or 
                             cloc-diff.xsl if --diff is also given).  
                             This switch forces --xml on.
   --yaml                    Write the results in YAML.

";
#  Help information for options not yet implemented:
#  --inline                  Process comments that appear at the end
#                            of lines containing code.
#  --html                    Create HTML files of each input file showing
#                            comment and code lines in different colors.

$| = 1;  # flush STDOUT
my $start_time = time();
my (
    $opt_categorized          ,
    $opt_found                ,
    @opt_force_lang           ,
    $opt_lang_no_ext          ,
    @opt_script_lang          ,
    $opt_diff                 ,
    $opt_diff_alignment       ,
    $opt_html                 ,
    $opt_ignored              ,
    $opt_counted              ,
    $opt_show_ext             ,
    $opt_show_lang            ,
    $opt_progress_rate        ,
    $opt_print_filter_stages  ,
    $opt_v                    ,
    $opt_version              ,
    $opt_exclude_lang         ,
    $opt_exclude_list_file    ,
    $opt_exclude_dir          ,
    $opt_read_lang_def        ,
    $opt_write_lang_def       ,
    $opt_strip_comments       ,
    $opt_original_dir         ,
    $opt_quiet                ,
    $opt_report_file          ,
    $opt_sdir                 ,
    $opt_sum_reports          ,
    $opt_unicode              ,
    $opt_no3                  ,   # accept it but don't use it
    $opt_3                    ,
    $opt_extract_with         ,
    $opt_by_file              ,
    $opt_by_file_by_lang      ,
    $opt_xml                  ,
    $opt_xsl                  ,
    $opt_yaml                 ,
    $opt_csv                  ,
	$opt_match_f              ,
	$opt_not_match_f          ,
	$opt_match_d              ,
	$opt_not_match_d          ,
	$opt_skip_uniqueness      ,
	$opt_list_file            ,
	$opt_help                 ,
	$opt_skip_win_hidden      ,
	$opt_read_binary_files    ,
	$opt_sql                  ,
	$opt_sql_append           ,
	$opt_sql_project          ,
	$opt_inline               ,
    $opt_exclude_ext          ,
    $opt_ignore_whitespace    ,
    $opt_ignore_case          ,
    $opt_follow_links         ,
    $opt_autoconf             ,
    $opt_sum_one              ,
   );
my $getopt_success = GetOptions(
   "by_file|by-file"                         => \$opt_by_file             ,
   "by_file_by_lang|by-file-by-lang"         => \$opt_by_file_by_lang     ,
   "categorized=s"                           => \$opt_categorized         ,
   "counted=s"                               => \$opt_counted             ,
   "exclude_lang|exclude-lang=s"             => \$opt_exclude_lang        ,
   "exclude_dir|exclude-dir=s"               => \$opt_exclude_dir         ,
   "exclude_list_file|exclude-list-file=s"   => \$opt_exclude_list_file   ,
   "extract_with|extract-with=s"             => \$opt_extract_with        , 
   "found=s"                                 => \$opt_found               ,
   "diff"                                    => \$opt_diff                ,
   "diff-alignment|diff_alignment=s"         => \$opt_diff_alignment      ,
   "html"                                    => \$opt_html                ,
   "ignored=s"                               => \$opt_ignored             ,
   "quiet"                                   => \$opt_quiet               ,
   "read_lang_def|read-lang-def=s"           => \$opt_read_lang_def       ,
   "show_ext|show-ext:s"                     => \$opt_show_ext            ,
   "show_lang|show-lang:s"                   => \$opt_show_lang           ,
   "progress_rate|progress-rate=i"           => \$opt_progress_rate       ,
   "print_filter_stages|print-filter-stages" => \$opt_print_filter_stages ,
   "report_file|report-file=s"               => \$opt_report_file         ,
   "out=s"                                   => \$opt_report_file         ,
   "script_lang|script-lang=s"               => \@opt_script_lang         ,
   "sdir=s"                                  => \$opt_sdir                ,
   "skip_uniqueness|skip-uniqueness"         => \$opt_skip_uniqueness     ,
   "strip_comments|strip-comments=s"         => \$opt_strip_comments      ,
   "original_dir|original-dir"               => \$opt_original_dir        ,
   "sum_reports|sum-reports"                 => \$opt_sum_reports         ,
   "unicode"                                 => \$opt_unicode             ,
   "no3"                                     => \$opt_no3                 ,  # ignored
   "3"                                       => \$opt_3                   ,
   "v:i"                                     => \$opt_v                   ,
   "version"                                 => \$opt_version             ,
   "write_lang_def|write-lang-def=s"         => \$opt_write_lang_def      ,
   "xml"                                     => \$opt_xml                 ,
   "xsl=s"                                   => \$opt_xsl                 ,
   "force_lang|force-lang=s"                 => \@opt_force_lang          ,
   "lang_no_ext|lang-no-ext=s"               => \$opt_lang_no_ext         ,
   "yaml"                                    => \$opt_yaml                ,
   "csv"                                     => \$opt_csv                 ,
   "match_f|match-f=s"                       => \$opt_match_f             ,
   "not_match_f|not-match-f=s"               => \$opt_not_match_f         ,
   "match_d|match-d=s"                       => \$opt_match_d             ,
   "not_match_d|not-match-d=s"               => \$opt_not_match_d         ,
   "list_file|list-file=s"                   => \$opt_list_file           ,
   "help"                                    => \$opt_help                ,
   "skip_win_hidden|skip-win-hidden"         => \$opt_skip_win_hidden     ,
   "read_binary_files|read-binary-files"     => \$opt_read_binary_files   ,
   "sql=s"                                   => \$opt_sql                 ,
   "sql_project|sql-project=s"               => \$opt_sql_project         ,
   "sql_append|sql-append"                   => \$opt_sql_append          ,
   "inline"                                  => \$opt_inline              ,
   "exclude_ext|exclude-ext=s"               => \$opt_exclude_ext         ,
   "ignore_whitespace|ignore-whitespace"     => \$opt_ignore_whitespace   ,
   "ignore_case|ignore-case"                 => \$opt_ignore_case         ,
   "follow_links|follow-links"               => \$opt_follow_links        ,
   "autoconf"                                => \$opt_autoconf            ,
   "sum_one|sum-one"                         => \$opt_sum_one             ,
  );
$opt_by_file  = 1 if defined  $opt_by_file_by_lang;
my $CLOC_XSL = "cloc.xsl"; # created with --xsl
   $CLOC_XSL = "cloc-diff.xsl" if $opt_diff;
die "\n" unless $getopt_success;
die $usage if $opt_help;
my %Exclude_Language = ();
   %Exclude_Language = map { $_ => 1 } split(/,/, $opt_exclude_lang) 
        if $opt_exclude_lang;
my %Exclude_Dir      = ();
   %Exclude_Dir      = map { $_ => 1 } split(/,/, $opt_exclude_dir ) 
        if $opt_exclude_dir ;
# Forcibly exclude .svn, .cvs, .hg directories.  The contents of these
# directories often conflict with files of interest.
$opt_exclude_dir       = 1;
$Exclude_Dir{".svn"}   = 1;
$Exclude_Dir{".cvs"}   = 1;
$Exclude_Dir{".hg"}    = 1;
$opt_diff              = 1 if $opt_diff_alignment;
$opt_exclude_ext       = "" unless $opt_exclude_ext;
$opt_ignore_whitespace = 0  unless $opt_ignore_whitespace;
$opt_ignore_case       = 0  unless $opt_ignore_case;       
$opt_lang_no_ext       = 0  unless $opt_lang_no_ext;
$opt_follow_links      = 0  unless $opt_follow_links;

# Options defaults:
$opt_progress_rate = 100 unless defined $opt_progress_rate;
if (!defined $opt_v) {
    $opt_v  = 0;
} elsif (!$opt_v) {
    $opt_v  = 1;
}
if (defined $opt_xsl) {
    $opt_xsl = $CLOC_XSL if $opt_xsl eq "1";
    $opt_xml = 1;
}
my $skip_generate_report = 0;
$opt_sql = 0 unless defined $opt_sql;
if ($opt_sql eq "1") { # stream SQL output to STDOUT
    $opt_quiet            = 1;
    $skip_generate_report = 1;
    $opt_by_file          = 1;
    $opt_sum_reports      = 0;
    $opt_progress_rate    = 0;
} elsif ($opt_sql)  { # write SQL output to a file
    $opt_by_file          = 1;
    $skip_generate_report = 1;
    $opt_sum_reports      = 0;
}
die $usage unless defined $opt_version         or
                  defined $opt_show_lang       or
                  defined $opt_show_ext        or
                  defined $opt_write_lang_def  or
                  defined $opt_list_file       or
                  defined $opt_xsl             or
                  scalar @ARGV >= 1;
die "--diff requires at least two arguments\n" 
    if $opt_diff and scalar @ARGV < 2;
if ($opt_version) {
    printf "$VERSION\n";
    exit;
}
# 1}}}
# Step 1:  Initialize global constants.        {{{1
#
my $nFiles_Found = 0;  # updated in make_file_list
my (%Language_by_Extension, %Language_by_Script,
    %Filters_by_Language, %Not_Code_Extension, %Not_Code_Filename,
    %Language_by_File, %Scale_Factor, %Known_Binary_Archives,
    %EOL_Continuation_re,
   );
my $ALREADY_SHOWED_HEADER = 0;
my $ALREADY_SHOWED_XML_SECTION = 0;
my %Error_Codes = ( 'Unable to read'                => -1,
                    'Neither file nor directory'    => -2, 
                    'Diff error (quoted comments?)' => -3, 
                  );
if ($opt_read_lang_def) {
    read_lang_def(
        $opt_read_lang_def     , #        Sample values:
        \%Language_by_Extension, # Language_by_Extension{f}    = 'Fortran 77' 
        \%Language_by_Script   , # Language_by_Script{sh}      = 'Bourne Shell'
        \%Language_by_File     , # Language_by_File{makefile}  = 'make'
        \%Filters_by_Language  , # Filters_by_Language{Bourne Shell}[0] = 
                                 #      [ 'remove_matches' , '^\s*#'  ]
        \%Not_Code_Extension   , # Not_Code_Extension{jpg}     = 1
        \%Not_Code_Filename    , # Not_Code_Filename{README}   = 1
        \%Scale_Factor         , # Scale_Factor{Perl}          = 4.0
        \%EOL_Continuation_re  , # EOL_Continuation_re{C++}    = '\\$'
        );
} else {
    set_constants(               #
        \%Language_by_Extension, # Language_by_Extension{f}    = 'Fortran 77' 
        \%Language_by_Script   , # Language_by_Script{sh}      = 'Bourne Shell'
        \%Language_by_File     , # Language_by_File{makefile}  = 'make'
        \%Filters_by_Language  , # Filters_by_Language{Bourne Shell}[0] = 
                                 #      [ 'remove_matches' , '^\s*#'  ]
        \%Not_Code_Extension   , # Not_Code_Extension{jpg}     = 1
        \%Not_Code_Filename    , # Not_Code_Filename{README}   = 1
        \%Scale_Factor         , # Scale_Factor{Perl}          = 4.0
        \%Known_Binary_Archives, # Known_Binary_Archives{.tar} = 1
        \%EOL_Continuation_re  , # EOL_Continuation_re{C++}    = '\\$'
        );
}
if ($opt_lang_no_ext and !defined $Filters_by_Language{$opt_lang_no_ext}) {
    die_unknown_lang($opt_lang_no_ext, "--lang-no-ext")
}

# Process command line provided extention-to-language mapping overrides.
# Make a hash of known languages in lower case for easier matching.
my %Recognized_Language_lc = (); # key = language name in lc, value = true name
foreach my $language (keys %Filters_by_Language) {
    my $lang_lc = lc $language;
    $Recognized_Language_lc{$lang_lc} = $language;
}
my %Forced_Extension = (); # file name extensions which user wants to count
my $All_One_Language = 0;  # set to !0 if --force-lang's <ext> is missing
foreach my $pair (@opt_force_lang) {
    my ($lang, $extension) = split(',', $pair);
    my $lang_lc = lc $lang;
    if (defined $extension) {
        $Forced_Extension{$extension} = $lang;

        die_unknown_lang($lang, "--force-lang")
            unless $Recognized_Language_lc{$lang_lc}; 

        $Language_by_Extension{$extension} = $Recognized_Language_lc{$lang_lc};
    } else {
        # the scary case--count everything as this language
        $All_One_Language = $Recognized_Language_lc{$lang_lc};
    }
}

foreach my $pair (@opt_script_lang) {
    my ($lang, $script_name) = split(',', $pair);
    my $lang_lc = lc $lang;
    if (!defined $script_name) {
        die "The --script-lang option requires a comma separated pair of ".
            "strings.\n";
    }

    die_unknown_lang($lang, "--script-lang")
        unless $Recognized_Language_lc{$lang_lc}; 

    $Language_by_Script{$script_name} = $Recognized_Language_lc{$lang_lc};
}

# If user provided file extensions to ignore, add these to
# the exclusion list.
foreach my $ext (map { $_ => 1 } split(/,/, $opt_exclude_ext ) ) {
    $ext = lc $ext if $ON_WINDOWS;
    $Not_Code_Extension{$ext} = 1;
}

# If SQL output is requested, keep track of directory names generated by 
# File::Temp::tempdir and used to temporarily hold the results of compressed
# archives.  Contents of the SQL table 't' will be much cleaner if these
# meaningless directory names are stripped from the front of files pulled
# from the archives.
my %TEMP_DIR = ();

# invert %Language_by_Script hash to get an easy-to-look-up list of known
# scripting languages
my %Script_Language = map { $_ => 1 } values %Language_by_Script ;
# 1}}}
# Step 2:  Early exits for display, summation. {{{1
#
print_extension_info($opt_show_ext ) if defined $opt_show_ext ;
print_language_info( $opt_show_lang) if defined $opt_show_lang;
exit if (defined $opt_show_ext) or (defined $opt_show_lang);

#print "Before glob have [", join(",", @ARGV), "]\n";
@ARGV = windows_glob(@ARGV) if $ON_WINDOWS;
#print "after  glob have [", join(",", @ARGV), "]\n";

if ($opt_sum_reports and $opt_diff) {
    my @results = ();
    if ($opt_list_file) { # read inputs from the list file
        my @list = read_list_file($opt_list_file);
        @results = combine_diffs(\@list);
    } else { # get inputs from the command line
        @results = combine_diffs(\@ARGV);
    }
    if ($opt_report_file) {
        write_file($opt_report_file, @results);
    } else {
        print "\n", join("\n", @results), "\n";
    }
    exit;
}
if ($opt_sum_reports) {
    my %Results = ();
    foreach my $type( "by language", "by report file" ) {
        my $found_lang = undef; 
        if ($opt_list_file) { # read inputs from the list file
            my @list = read_list_file($opt_list_file);
            $found_lang = combine_results(\@list, 
                                           $type, 
                                          \%{$Results{ $type }}, 
                                          \%Filters_by_Language );
        } else { # get inputs from the command line
            $found_lang = combine_results(\@ARGV, 
                                           $type, 
                                          \%{$Results{ $type }}, 
                                          \%Filters_by_Language );
        }
        next unless %Results;
        my $end_time = time();
        my @results  = generate_report($VERSION, $end_time - $start_time,
                                       $type,
                                      \%{$Results{ $type }}, \%Scale_Factor);
        if ($opt_report_file) {
            my $ext  = ".lang";
               $ext  = ".file" unless $type eq "by language";
            next if !$found_lang and  $ext  eq ".lang";
            write_file($opt_report_file . $ext, @results);
        } else {
            print "\n", join("\n", @results), "\n";
        }
    }
    exit;
}
if ($opt_write_lang_def) {
    write_lang_def($opt_write_lang_def   ,
                  \%Language_by_Extension,
                  \%Language_by_Script   ,
                  \%Language_by_File     ,
                  \%Filters_by_Language  ,
                  \%Not_Code_Extension   ,
                  \%Not_Code_Filename    ,
                  \%Scale_Factor         ,
                  \%EOL_Continuation_re  ,
                  );
    exit;
}
# 1}}}
# Step 3:  Create a list of files to consider. {{{1
#  a) If inputs are binary archives, first cd to a temp
#     directory, expand the archive with the user-given
#     extraction tool, then add the temp directory to
#     the list of dirs to process.
#  b) Create a list of every file that might contain source
#     code.  Ignore binary files, zero-sized files, and
#     any file in a directory the user says to exclude.
#  c) Determine the language for each file in the list.
#
my @binary_archive = ();
my $cwd            = cwd();
if ($opt_extract_with) {
#print "cwd main = [$cwd]\n";
    my @extract_location = ();
    foreach my $bin_file (@ARGV) {
        my $extract_dir = tempdir( CLEANUP => 1 );  # 1 = delete on exit
        $TEMP_DIR{ $extract_dir } = 1 if $opt_sql;
        print "mkdir $extract_dir\n" if $opt_v;
        print "cd    $extract_dir\n" if $opt_v;
        chdir $extract_dir;
        my $bin_file_full_path = "";
        if (File::Spec->file_name_is_absolute( $bin_file )) {
            $bin_file_full_path = $bin_file;
#print "bin_file_full_path (was ful) = [$bin_file_full_path]\n";
        } else {
            $bin_file_full_path = File::Spec->catfile( $cwd, $bin_file );
#print "bin_file_full_path (was rel) = [$bin_file_full_path]\n";
        }
        my     $extract_cmd = uncompress_archive_cmd($bin_file_full_path);
        print  $extract_cmd, "\n" if $opt_v;
        system $extract_cmd;
        push @extract_location, $extract_dir;
        chdir $cwd;
    }
    # It is possible that the binary archive itself contains additional
    # files compressed the same way (true for Java .ear files).  Go
    # through all the files that were extracted, see if they are binary
    # archives and try to extract them.  Lather, rinse, repeat.
    my $binary_archives_exist = 1;
    my $count_binary_archives = 0;
    my $previous_count        = 0;
    while ($binary_archives_exist) {
        @binary_archive = ();
        foreach my $dir (@extract_location) {
            find(\&archive_files, $dir);  # populates global @binary_archive
        }
        foreach my $archive (@binary_archive) {
            my     $extract_dir = tempdir( CLEANUP => 1 ); # 1 = delete on exit
            $TEMP_DIR{ $extract_dir } = 1 if $opt_sql;
            print "mkdir $extract_dir\n" if $opt_v;
            print "cd    $extract_dir\n" if $opt_v;
            chdir  $extract_dir;

            my     $extract_cmd = uncompress_archive_cmd($archive);
            print  $extract_cmd, "\n" if $opt_v;
            system $extract_cmd;
            push @extract_location, $extract_dir;
            unlink $archive;  # otherwise will be extracting it forever 
        }
        $count_binary_archives = scalar @binary_archive;
        if ($count_binary_archives == $previous_count) {
            $binary_archives_exist = 0;
        }
        $previous_count = $count_binary_archives;
    }
    chdir $cwd;

    @ARGV = @extract_location;
} else {
    # see if any of the inputs need to be auto-uncompressed &/or expanded
    my @updated_ARGS = ();
    foreach my $Arg (@ARGV) {
        if (is_dir($Arg)) {
            push @updated_ARGS, $Arg;
            next;
        }
        my $full_path = "";
        if (File::Spec->file_name_is_absolute( $Arg )) {
            $full_path = $Arg;
        } else {
            $full_path = File::Spec->catfile( $cwd, $Arg );
        }
#print "full_path = [$full_path]\n";
        my $extract_cmd = uncompress_archive_cmd($full_path);
        if ($extract_cmd) {
            my     $extract_dir = tempdir( CLEANUP => 1 ); # 1 = delete on exit
            $TEMP_DIR{ $extract_dir } = 1 if $opt_sql;
            print "mkdir $extract_dir\n" if $opt_v;
            print "cd    $extract_dir\n" if $opt_v;
            chdir  $extract_dir;
            print  $extract_cmd, "\n" if $opt_v;
            system $extract_cmd;
            push @updated_ARGS, $extract_dir;
            chdir $cwd;
        } else {
            # this is a conventional, uncompressed, unarchived file
            # or a directory; keep as-is
            push @updated_ARGS, $Arg;
        }
    }
    @ARGV = @updated_ARGS;
}
# 1}}}
my @Errors    = ();
my @file_list = ();  # global variable updated in files()
my %Ignored   = ();  # files that are not counted (language not recognized or
                     # problems reading the file)
my @Lines_Out = ();
if ($opt_diff) {
# Step 4:  Separate code from non-code files. {{{1
my @fh            = ();
my @files_for_set = ();
# make file lists for each separate argument
if ($opt_exclude_list_file) {
    process_exclude_list_file($opt_exclude_list_file, 
                             \%Exclude_Dir,
                             \%Ignored);
}
for (my $i = 0; $i < scalar @ARGV; $i++) {
    push @fh, 
         make_file_list([ $ARGV[$i] ], \%Error_Codes, \@Errors, \%Ignored);
    @{$files_for_set[$i]} = @file_list;
    @file_list = ();
}
# 1}}}
# Step 5:  Remove duplicate files.             {{{1
#
my %Language           = ();
my %unique_source_file = ();
my $n_set = 0;
foreach my $FH (@fh) {  # loop over each pair of file sets
    ++$n_set;
    remove_duplicate_files($FH, 
                               \%{$Language{$FH}}               , 
                               \%{$unique_source_file{$FH}}     , 
                          \%Error_Codes                         , 
                               \@Errors                         , 
                               \%Ignored                        );
    printf "%2d: %8d unique file%s.                          \r", 
        $n_set,
        plural_form(scalar keys %unique_source_file) 
        unless $opt_quiet;
}
# 1}}}
# Step 6:  Count code, comments, blank lines.  {{{1
#
my %Results_by_Language = ();
my %Results_by_File     = ();
my %Delta_by_Language   = ();
my %Delta_by_File       = ();
my $nFiles_added        = 0;
my $nFiles_removed      = 0;
my $nFiles_modified     = 0;
my $nFiles_same         = 0;

foreach (my $F = 0; $F < scalar @fh - 1; $F++) { 
    # loop over file sets; do diff between set $F to $F+1

    my $nCounted = 0;

    my @file_pairs    = ();
    my @files_added   = ();
    my @files_removed = ();

    align_by_pairs(\%{$unique_source_file{$fh[$F  ]}}    , # in
                   \%{$unique_source_file{$fh[$F+1]}}    , # in
                   \@files_added                         , # out
                   \@files_removed                       , # out
                   \@file_pairs                          , # out
                   );
    if (!@file_pairs) {
        # Special case where all files were either added or deleted.
        # In this case, one of these arrays will be empty: 
        #   @files_added, @files_removed
        # so loop over both to cover both cases.
        my $status = @files_added ? 'added' : 'removed';
        my $offset = @files_added ? 1       : 0        ;
        foreach my $file (@files_added, @files_removed) {
            my $Lang = $Language{$fh[$F+$offset]}{$file};
            my ($all_line_count,
                $blank_count   ,
                $comment_count ,
               ) = call_counter($file, $Lang, \@Errors);
            my $code_count = $all_line_count-$blank_count-$comment_count;
            if ($opt_by_file) {
                $Delta_by_File{$file}{'code'   }{$status} += $code_count   ;
                $Delta_by_File{$file}{'blank'  }{$status} += $blank_count  ;
                $Delta_by_File{$file}{'comment'}{$status} += $comment_count;
                $Delta_by_File{$file}{'lang'   }{$status}  = $Lang         ;
                $Delta_by_File{$file}{'nFiles' }{$status} += 1             ;
            }
            $Delta_by_Language{$Lang}{'code'   }{$status} += $code_count   ;
            $Delta_by_Language{$Lang}{'blank'  }{$status} += $blank_count  ;
            $Delta_by_Language{$Lang}{'comment'}{$status} += $comment_count;
        }
    }
   #use Data::Dumper::Simple;
   #use Data::Dumper;
   #print Dumper(\@files_added, \@files_removed, \@file_pairs);
    my @alignment = (); # only  used if --diff-alignment
#print "after align_by_pairs:\n";

#print "added:\n";
    push @alignment, sprintf "Files added: %d\n", scalar @files_added
        if $opt_diff_alignment;
    foreach my $f (@files_added) {
#printf "%10s -> %s\n", $f, $Language{$fh[$F+1]}{$f};
        # Don't proceed unless the file (both L and R versions)
        # is in a known language.
        next if $Language{$fh[$F+1]}{$f} eq "(unknown)";
        next if $Exclude_Language{$Language{$fh[$F+1]}{$f}};
        push @alignment, sprintf "  + %s ; %s\n", $f, $Language{$fh[$F+1]}{$f}
            if $opt_diff_alignment;
        ++$Delta_by_Language{ $Language{$fh[$F+1]}{$f} }{'nFiles'}{'added'};
        # Additionally, add contents of file $f to 
        #        Delta_by_File{$f}{comment/blank/code}{'added'}
        #        Delta_by_Language{$lang}{comment/blank/code}{'added'}
        my ($all_line_count,
            $blank_count   ,
            $comment_count ,
           ) = call_counter($f, $Language{$fh[$F+1]}{$f}, \@Errors);
        $Delta_by_Language{ $Language{$fh[$F+1]}{$f} }{'comment'}{'added'} +=
            $comment_count;
        $Delta_by_Language{ $Language{$fh[$F+1]}{$f} }{'blank'}{'added'}   +=
            $blank_count;
        $Delta_by_Language{ $Language{$fh[$F+1]}{$f} }{'code'}{'added'}    +=
            $all_line_count - $blank_count - $comment_count;
        $Delta_by_File{ $f }{'comment'}{'added'} = $comment_count;
        $Delta_by_File{ $f }{'blank'}{'added'}   = $blank_count;
        $Delta_by_File{ $f }{'code'}{'added'}    = 
            $all_line_count - $blank_count - $comment_count;
    }
    push @alignment, "\n";

#print "removed:\n";
    push @alignment, sprintf "Files removed: %d\n", scalar @files_removed
        if $opt_diff_alignment;
    foreach my $f (@files_removed) {
        # Don't proceed unless the file (both L and R versions)
        # is in a known language.
        next if $Language{$fh[$F  ]}{$f} eq "(unknown)";
        next if $Exclude_Language{$Language{$fh[$F  ]}{$f}};
        ++$Delta_by_Language{ $Language{$fh[$F  ]}{$f} }{'nFiles'}{'removed'};
        push @alignment, sprintf "  - %s ; %s\n", $f, $Language{$fh[$F]}{$f}
            if $opt_diff_alignment;
#printf "%10s -> %s\n", $f, $Language{$fh[$F  ]}{$f};
        # Additionally, add contents of file $f to 
        #        Delta_by_File{$f}{comment/blank/code}{'removed'}
        #        Delta_by_Language{$lang}{comment/blank/code}{'removed'}
        my ($all_line_count,
            $blank_count   ,
            $comment_count ,
           ) = call_counter($f, $Language{$fh[$F  ]}{$f}, \@Errors);
        $Delta_by_Language{ $Language{$fh[$F  ]}{$f} }{'comment'}{'removed'} +=
            $comment_count;
        $Delta_by_Language{ $Language{$fh[$F  ]}{$f} }{'blank'}{'removed'}   +=
            $blank_count;
        $Delta_by_Language{ $Language{$fh[$F  ]}{$f} }{'code'}{'removed'}    +=
            $all_line_count - $blank_count - $comment_count;
        $Delta_by_File{ $f }{'comment'}{'removed'} = $comment_count;
        $Delta_by_File{ $f }{'blank'}{'removed'}   = $blank_count;
        $Delta_by_File{ $f }{'code'}{'removed'}    = 
            $all_line_count - $blank_count - $comment_count;
    }
    push @alignment, "\n";

    push @alignment, sprintf "File pairs compared: %d\n", scalar @file_pairs
        if $opt_diff_alignment;
#print "Language=\n", Dumper(\%Language);
    foreach my $pair (@file_pairs) {
        my $file_L = $pair->[0];
        my $file_R = $pair->[1];
        my $Lang_L = $Language{$fh[$F  ]}{$file_L};
        my $Lang_R = $Language{$fh[$F+1]}{$file_R};
#print "main step 6 file_L=$file_L    file_R=$file_R\n";
        ++$nCounted;
        printf "Counting:  %d\r", $nCounted 
            unless (!$opt_progress_rate or ($nCounted % $opt_progress_rate));
        next if $Ignored{$file_L};

        # filter out excluded or unrecognized languages
        if ($Exclude_Language{$Lang_L} or $Exclude_Language{$Lang_R}) {
            $Ignored{$file_L} = "--exclude-lang=$Lang_L}";
            $Ignored{$file_R} = "--exclude-lang=$Lang_R}";
            next;
        }
        if (!defined @{$Filters_by_Language{$Lang_L} } or
            !defined @{$Filters_by_Language{$Lang_R} }
           ) {
            if (($Lang_L eq "(unknown)") or ($Lang_R eq "(unknown)")) {
                $Ignored{$fh[$F  ]}{$file_L} = "language unknown (#1)";
                $Ignored{$fh[$F+1]}{$file_R} = "language unknown (#1)";
            } else {
                $Ignored{$fh[$F  ]}{$file_L} = "missing Filters_by_Language{$Lang_L}";
                $Ignored{$fh[$F+1]}{$file_R} = "missing Filters_by_Language{$Lang_R}";
            }
            next;
        }

#print "DIFF($file_L, $file_R)\n";
        # step 0: compare the two files' contents 
        chomp ( my @lines_L = read_file($file_L) );
        chomp ( my @lines_R = read_file($file_R) );
        my $language_file_L = "";
        if (defined $Language{$fh[$F]}{$file_L}) {
            $language_file_L = $Language{$fh[$F]}{$file_L};
        } else {
            # files $file_L and $file_R do not contain known language
            next;
        }
        my $contents_are_same = 1;
        if (scalar @lines_L == scalar @lines_R) {
            # same size, must compare line-by-line
            for (my $i = 0; $i < scalar @lines_L; $i++) {
                if ($lines_L[$i] ne $lines_R[$i]) {
                    $contents_are_same = 0;
                    last;
                }
            }
            if ($contents_are_same) {
                ++$Delta_by_Language{$language_file_L}{'nFiles'}{'same'};
            } else {
                ++$Delta_by_Language{$language_file_L}{'nFiles'}{'modified'};
            }
        } else {
            $contents_are_same = 0;
            # different sizes, contents have changed
            ++$Delta_by_Language{$language_file_L}{'nFiles'}{'modified'};
        }
        if ($opt_diff_alignment) {
            my $str =  "$file_L | $file_R ; $language_file_L";
            if ($contents_are_same) {
                push @alignment, "  == $str";
            } else {
                push @alignment, "  != $str";
            }
        }

        # step 1: identify comments in both files
#print "Diff blank removal L language= $Lang_L";
#print " scalar(lines_L)=", scalar @lines_L, "\n";
        my @original_minus_blanks_L 
                    = rm_blanks(  \@lines_L, $Lang_L, \%EOL_Continuation_re);
#print "1: scalar(original_minus_blanks_L)=", scalar @original_minus_blanks_L, "\n";
        @lines_L    = @original_minus_blanks_L;
#print "2: scalar(lines_L)=", scalar @lines_L, "\n";
        @lines_L    = add_newlines(\@lines_L); # compensate for rm_comments()
        @lines_L    = rm_comments( \@lines_L, $Lang_L, $file_L,
                                   \%EOL_Continuation_re);
#print "3: scalar(lines_L)=", scalar @lines_L, "\n";

#print "Diff blank removal R language= $Lang_R\n";
        my @original_minus_blanks_R 
                    = rm_blanks(  \@lines_R, $Lang_R, \%EOL_Continuation_re);
        @lines_R    = @original_minus_blanks_R;
        @lines_R    = add_newlines(\@lines_R); # taken away by rm_comments()
        @lines_R    = rm_comments( \@lines_R, $Lang_R, $file_R,
                                   \%EOL_Continuation_re);

        my (@diff_LL, @diff_LR, );
        array_diff( $file_L                  ,   # in
                   \@original_minus_blanks_L ,   # in
                   \@lines_L                 ,   # in
                   "comment"                 ,   # in
                   \@diff_LL, \@diff_LR      ,   # out
                   \@Errors);                    # in/out

        my (@diff_RL, @diff_RR, );
        array_diff( $file_R                  ,   # in
                   \@original_minus_blanks_R ,   # in
                   \@lines_R                 ,   # in
                   "comment"                 ,   # in
                   \@diff_RL, \@diff_RR      ,   # out
                   \@Errors);                    # in/out
        # each line of each file is now classified as
        # code or comment

#use Data::Dumper; 
#print Dumper("diff_LL", \@diff_LL, "diff_LR", \@diff_LR, );
#print Dumper("diff_RL", \@diff_RL, "diff_RR", \@diff_RR, );
#die;
        # step 2: separate code from comments for L and R files
        my @code_L = ();
        my @code_R = ();
        my @comm_L = ();
        my @comm_R = ();
        foreach my $line_info (@diff_LL) {
            if      ($line_info->{'type'} eq "code"   ) {
                push @code_L, $line_info->{char};
            } elsif ($line_info->{'type'} eq "comment") {
                push @comm_L, $line_info->{char};
            } else {
                die "Diff unexpected line type ",
                    $line_info->{'type'}, "for $file_L line ",
                    $line_info->{'lnum'};
            }
        }
        foreach my $line_info (@diff_RL) {
            if      ($line_info->{type} eq "code"   ) {
                push @code_R, $line_info->{'char'};
            } elsif ($line_info->{type} eq "comment") {
                push @comm_R, $line_info->{'char'};
            } else {
                die "Diff unexpected line type ",
                    $line_info->{'type'}, "for $file_R line ",
                    $line_info->{'lnum'};
            }
        }

        if ($opt_ignore_whitespace) {
            # strip all whitespace from each line of source code
            # and comments then use these stripped arrays in diffs
            foreach (@code_L) { s/\s+//g }
            foreach (@code_R) { s/\s+//g }
            foreach (@comm_L) { s/\s+//g }
            foreach (@comm_R) { s/\s+//g }
        }
        if ($opt_ignore_case) {
            # change all text to lowercase in diffs
            foreach (@code_L) { $_ = lc }
            foreach (@code_R) { $_ = lc }
            foreach (@comm_L) { $_ = lc }
            foreach (@comm_R) { $_ = lc }
        }
        # step 3: compute code diffs
        array_diff("$file_L v. $file_R"   ,   # in
                   \@code_L               ,   # in
                   \@code_R               ,   # in
                   "revision"             ,   # in
                   \@diff_LL, \@diff_LR   ,   # out
                   \@Errors);                 # in/out
#print Dumper("diff_LL", \@diff_LL, "diff_LR", \@diff_LR, );
#print Dumper("diff_LR", \@diff_LR);
        foreach my $line_info (@diff_LR) {
            my $status = $line_info->{'desc'}; # same|added|removed|modified
            ++$Delta_by_Language{$Lang_L}{'code'}{$status};
            if ($opt_by_file) {
                ++$Delta_by_File{$file_L}{'code'}{$status};
            }
        }
#use Data::Dumper;
#print Dumper("code diffs:", \@diff_LL, \@diff_LR);

        # step 4: compute comment diffs
        array_diff("$file_L v. $file_R"   ,   # in
                   \@comm_L               ,   # in
                   \@comm_R               ,   # in
                   "revision"             ,   # in
                   \@diff_LL, \@diff_LR   ,   # out
                   \@Errors);                 # in/out
#print Dumper("comment diff_LR", \@diff_LR);
        foreach my $line_info (@diff_LR) {
            my $status = $line_info->{'desc'}; # same|added|removed|modified
            ++$Delta_by_Language{$Lang_L}{'comment'}{$status};
            if ($opt_by_file) {
                ++$Delta_by_File{$file_L}{'comment'}{$status};
            }
        }
#print Dumper("comment diffs:", \@diff_LL, \@diff_LR);
#die; here=  need to save original line number in diff result for html display

        # step 5: compute difference in blank lines (kind of pointless)
        my ($all_line_count_L,
            $blank_count_L   ,
            $comment_count_L ,
           ) = call_counter($file_L, $Lang_L, \@Errors);

        my ($all_line_count_R,
            $blank_count_R   ,
            $comment_count_R ,
           ) = call_counter($file_R, $Lang_R, \@Errors);

        if ($blank_count_L <  $blank_count_R) {
            my $D = $blank_count_R - $blank_count_L;
            $Delta_by_Language{$Lang_L}{'blank'}{'added'}   += $D;
        } else {
            my $D = $blank_count_L - $blank_count_R;
            $Delta_by_Language{$Lang_L}{'blank'}{'removed'} += $D;
        }
        if ($opt_by_file) {
            if ($blank_count_L <  $blank_count_R) {
                my $D = $blank_count_R - $blank_count_L;
                $Delta_by_File{$file_L}{'blank'}{'added'}   += $D;
            } else {
                my $D = $blank_count_L - $blank_count_R;
                $Delta_by_File{$file_L}{'blank'}{'removed'} += $D;
            }
        }

        my $code_count_L = $all_line_count_L-$blank_count_L-$comment_count_L;
        if ($opt_by_file) {
            $Results_by_File{$file_L}{'code'   } = $code_count_L    ;
            $Results_by_File{$file_L}{'blank'  } = $blank_count_L   ;
            $Results_by_File{$file_L}{'comment'} = $comment_count_L ;
            $Results_by_File{$file_L}{'lang'   } = $Lang_L          ;
            $Results_by_File{$file_L}{'nFiles' } = 1                ;
        } else {
            $Results_by_File{$file_L} = 1;  # just keep track of counted files
        }
   
        $Results_by_Language{$Lang_L}{'nFiles'}++;
        $Results_by_Language{$Lang_L}{'code'}    += $code_count_L   ;
        $Results_by_Language{$Lang_L}{'blank'}   += $blank_count_L  ;
        $Results_by_Language{$Lang_L}{'comment'} += $comment_count_L;
    }
    write_file($opt_diff_alignment, @alignment) if $opt_diff_alignment;

}
#use Data::Dumper;
#print Dumper("Delta_by_Language:"  , \%Delta_by_Language);
#print Dumper("Results_by_Language:", \%Results_by_Language);
#print Dumper("Delta_by_File:"      , \%Delta_by_File);
#print Dumper("Results_by_File:"    , \%Results_by_File);
#die;
my @ignored_reasons = map { "$_: $Ignored{$_}" } sort keys %Ignored;
write_file($opt_ignored, @ignored_reasons   ) if $opt_ignored;
write_file($opt_counted, sort keys %Results_by_File) if $opt_counted;
# 1}}}
# Step 7:  Assemble results.                      {{{1
#
my $end_time = time();
printf "%8d file%s ignored.                           \n", 
    plural_form(scalar keys %Ignored) unless $opt_quiet;
print_errors(\%Error_Codes, \@Errors) if @Errors;
if (!%Delta_by_Language) {
    print "Nothing to count.\n";
    exit;
}

if ($opt_by_file) {
    @Lines_Out = diff_report($VERSION, time() - $start_time,
                            "by file",
                            \%Delta_by_File, \%Scale_Factor);
} else {
    @Lines_Out = diff_report($VERSION, time() - $start_time,
                            "by language",
                            \%Delta_by_Language, \%Scale_Factor);
}

# 1}}}
} else {
# Step 4:  Separate code from non-code files. {{{1
my $fh = 0;
if ($opt_list_file) {
    my @list = read_list_file($opt_list_file);
    $fh = make_file_list(\@list, \%Error_Codes, \@Errors, \%Ignored);
} else {
    $fh = make_file_list(\@ARGV, \%Error_Codes, \@Errors, \%Ignored);
    #     make_file_list populates global variable @file_list via call to 
    #     File::Find's find() which in turn calls files()
}
if ($opt_exclude_list_file) {
    process_exclude_list_file($opt_exclude_list_file, 
                             \%Exclude_Dir,
                             \%Ignored);
}
if ($opt_skip_win_hidden and $ON_WINDOWS) {
    my @file_list_minus_hidded = ();
    # eval code to run on Unix without 'missing Win32::File module' error.
    my $win32_file_invocation = '
        use Win32::File;
        foreach my $F (@file_list) {
            my $attr = undef;
            Win32::File::GetAttributes($F, $attr);
            if ($attr & HIDDEN) {
                $Ignored{$F} = "Windows hidden file";
                print "Ignoring $F since it is a Windows hidden file\n" 
                    if $opt_v > 1;
            } else {
                push @file_list_minus_hidded, $F;
            }
        }';
    eval $win32_file_invocation;
    @file_list = @file_list_minus_hidded;
}
#printf "%8d file%s excluded.                     \n", 
#   plural_form(scalar keys %Ignored) 
#   unless $opt_quiet;
# die print ": ", join("\n: ", @file_list), "\n";
# 1}}}
# Step 5:  Remove duplicate files.             {{{1
#
my %Language           = ();
my %unique_source_file = ();
remove_duplicate_files($fh                          ,   # in 
                           \%Language               ,   # out
                           \%unique_source_file     ,   # out
                      \%Error_Codes                 ,   # in
                           \@Errors                 ,   # out
                           \%Ignored                );  # out
printf "%8d unique file%s.                              \n", 
    plural_form(scalar keys %unique_source_file) 
    unless $opt_quiet;
# 1}}}
# Step 6:  Count code, comments, blank lines.  {{{1
#

my %Results_by_Language = ();
my %Results_by_File     = ();
my $nCounted = 0;
foreach my $file (sort keys %unique_source_file) {
    ++$nCounted;
    printf "Counting:  %d\r", $nCounted 
        unless (!$opt_progress_rate or ($nCounted % $opt_progress_rate));
    next if $Ignored{$file};
    if ($Exclude_Language{$Language{$file}}) {
        $Ignored{$file} = "--exclude-lang=$Language{$file}";
        next;
    }
    if (!defined @{$Filters_by_Language{$Language{$file}} }) {
        if ($Language{$file} eq "(unknown)") {
            $Ignored{$file} = "language unknown (#1)";
        } else {
            $Ignored{$file} = "missing Filters_by_Language{$Language{$file}}";
        }
        next;
    }

    my ($all_line_count,
        $blank_count   ,
        $comment_count ,
       ) = call_counter($file, $Language{$file}, \@Errors);
    my $code_count = $all_line_count - $blank_count - $comment_count;
    if ($opt_by_file) {
        $Results_by_File{$file}{'code'   } = $code_count     ;
        $Results_by_File{$file}{'blank'  } = $blank_count    ;
        $Results_by_File{$file}{'comment'} = $comment_count  ;
        $Results_by_File{$file}{'lang'   } = $Language{$file};
        $Results_by_File{$file}{'nFiles' } = 1;
    } else {
        $Results_by_File{$file} = 1;  # just keep track of counted files
    }

    $Results_by_Language{$Language{$file}}{'nFiles'}++;
    $Results_by_Language{$Language{$file}}{'code'}    += $code_count   ;
    $Results_by_Language{$Language{$file}}{'blank'}   += $blank_count  ;
    $Results_by_Language{$Language{$file}}{'comment'} += $comment_count;
}
my @ignored_reasons = map { "$_: $Ignored{$_}" } sort keys %Ignored;
write_file($opt_ignored, @ignored_reasons   ) if $opt_ignored;
write_file($opt_counted, sort keys %Results_by_File) if $opt_counted;
# 1}}}
# Step 7:  Assemble results.                      {{{1
#
my $end_time = time();
printf "%8d file%s ignored.\n", plural_form(scalar keys %Ignored) 
    unless $opt_quiet;
print_errors(\%Error_Codes, \@Errors) if @Errors;
exit unless %Results_by_Language;

generate_sql($end_time - $start_time,
            \%Results_by_File, \%Scale_Factor) if $opt_sql;

exit if $skip_generate_report;
if      ($opt_by_file_by_lang) {
    push @Lines_Out, generate_report( $VERSION, $end_time - $start_time,
                                      "by file",
                                      \%Results_by_File,    \%Scale_Factor);
    push @Lines_Out, generate_report( $VERSION, $end_time - $start_time,
                                      "by language",
                                      \%Results_by_Language, \%Scale_Factor);
} elsif ($opt_by_file) {
    push @Lines_Out, generate_report( $VERSION, $end_time - $start_time,
                                      "by file",
                                      \%Results_by_File,    \%Scale_Factor);
} else {
    push @Lines_Out, generate_report( $VERSION, $end_time - $start_time,
                                      "by language",
                                      \%Results_by_Language, \%Scale_Factor);
}
# 1}}}
}
if ($opt_report_file) { write_file($opt_report_file, @Lines_Out); } 
else                  { print "\n", join("\n", @Lines_Out), "\n"; }

sub process_exclude_list_file {              # {{{1
    my ($list_file      , # in
        $rh_exclude_dir , # out
        $rh_ignored     , # out
       ) = @_;
    print "-> process_exclude_list_file($list_file)\n" if $opt_v > 2;
    # reject a specific set of files and/or directories
    my @reject_list   = read_list_file($list_file);
    my @file_reject_list = ();
    foreach my $F_or_D (@reject_list) {
        if (is_dir($F_or_D)) {
            $rh_exclude_dir->{$F_or_D} = 1;
        } elsif (is_file($F_or_D)) {
            push @file_reject_list, $F_or_D;
        }
    }

    # Normalize file names for better comparison.
    my %normalized_input   = normalize_file_names(@file_list);
    my %normalized_reject  = normalize_file_names(@file_reject_list);
    my %normalized_exclude = normalize_file_names(keys %{$rh_exclude_dir});
    foreach my $F (keys %normalized_input) {
        if ($normalized_reject{$F} or is_excluded($F, \%normalized_exclude)) {
            my $orig_F = $normalized_input{$F};
            $rh_ignored->{$orig_F} = "listed in exclusion file $opt_exclude_list_file";
            print "Ignoring $orig_F because it appears in $opt_exclude_list_file\n" 
                if $opt_v > 1;
        }
    }
    print "<- process_exclude_list_file\n" if $opt_v > 2;
} # 1}}}
sub combine_results {                        # {{{1
    # returns 1 if the inputs are categorized by language
    #         0 if no identifiable language was found
    my ($ra_report_files, # in
        $report_type    , # in  "by language" or "by report file"
        $rhh_count      , # out count{TYPE}{nFiles|code|blank|comment|scaled}
        $rhaa_Filters_by_Language , # in
       ) = @_;

    print "-> combine_results(report_type=$report_type)\n" if $opt_v > 2;
    my $found_language = 0;

    foreach my $file (@{$ra_report_files}) {
        my $IN = new IO::File $file, "r";
        if (!defined $IN) {
            warn "Unable to read $file; ignoring.\n";
            next;
        }
        while (<$IN>) {
            next if /^(http|Language|SUM|-----)/;
            if (!$opt_by_file  and
                m{^(.*?)\s+         # language
                   (\d+)\s+         # files
                   (\d+)\s+         # blank
                   (\d+)\s+         # comments
                   (\d+)\s+         # code
                   (                #    next four entries missing with -nno3
                   x\s+             # x
                   \d+\.\d+\s+      # scale
                   =\s+             # =
                   (\d+\.\d+)\s*    # scaled code
                   )?
                   $}x) {
                if ($report_type eq "by language") {
                    next unless defined @{$rhaa_Filters_by_Language->{$1}};
                    # above test necessary to avoid trying to sum reports
                    # of reports (which have no language breakdown).
                    $found_language = 1;
                    $rhh_count->{$1   }{'nFiles' } += $2;
                    $rhh_count->{$1   }{'blank'  } += $3;
                    $rhh_count->{$1   }{'comment'} += $4;
                    $rhh_count->{$1   }{'code'   } += $5;
                    $rhh_count->{$1   }{'scaled' } += $7 if $opt_3;
                } else {
                    $rhh_count->{$file}{'nFiles' } += $2;
                    $rhh_count->{$file}{'blank'  } += $3;
                    $rhh_count->{$file}{'comment'} += $4;
                    $rhh_count->{$file}{'code'   } += $5;
                    $rhh_count->{$file}{'scaled' } += $7 if $opt_3;
                }
            } elsif ($opt_by_file  and
                m{^(.*?)\s+         # language
                   (\d+)\s+         # blank
                   (\d+)\s+         # comments
                   (\d+)\s+         # code
                   (                #    next four entries missing with -nno3
                   x\s+             # x
                   \d+\.\d+\s+      # scale
                   =\s+             # =
                   (\d+\.\d+)\s*    # scaled code
                   )?
                   $}x) {
                if ($report_type eq "by language") {
                    next unless %{$rhaa_Filters_by_Language->{$1}};
                    # above test necessary to avoid trying to sum reports
                    # of reports (which have no language breakdown).
                    $found_language = 1;
                    $rhh_count->{$1   }{'nFiles' } +=  1;
                    $rhh_count->{$1   }{'blank'  } += $2;
                    $rhh_count->{$1   }{'comment'} += $3;
                    $rhh_count->{$1   }{'code'   } += $4;
                    $rhh_count->{$1   }{'scaled' } += $6 if $opt_3;
                } else {
                    $rhh_count->{$file}{'nFiles' } +=  1;
                    $rhh_count->{$file}{'blank'  } += $2;
                    $rhh_count->{$file}{'comment'} += $3;
                    $rhh_count->{$file}{'code'   } += $4;
                    $rhh_count->{$file}{'scaled' } += $6 if $opt_3;
                }
            }
        }
    }
    print "<- combine_results\n" if $opt_v > 2;
    return $found_language;

} # 1}}}
sub diff_report     {                        # {{{1
    # returns an array of lines containing the results
    print "-> diff_report\n" if $opt_v > 2;

    if ($opt_xml or $opt_yaml) {
        print "<- diff_report\n" if $opt_v > 2;
        return diff_xml_yaml_report(@_) 
    } elsif ($opt_csv) {
        print "<- diff_report\n" if $opt_v > 2;
        return diff_csv_report(@_) 
    }

    my ($version    , # in
        $elapsed_sec, # in
        $report_type, # in  "by language" | "by report file" | "by file"
        $rhhh_count , # in  count{TYPE}{nFiles|code|blank|comment}{a|m|r|s}
        $rh_scale   , # in
       ) = @_;

#print "diff_report: ", Dumper($rhhh_count), "\n";
    my @results       = ();

    my $languages     = ();
    my %sum           = (); # sum{nFiles|blank|comment|code}{same|modified|added|removed}
    my $max_len       = 0;
    foreach my $language (keys %{$rhhh_count}) {
        foreach my $V (qw(nFiles blank comment code)) {
            foreach my $S (qw(added same modified removed)) {
                $rhhh_count->{$language}{$V}{$S} = 0 unless
                    defined $rhhh_count->{$language}{$V}{$S};
                $sum{$V}{$S}  += $rhhh_count->{$language}{$V}{$S};
            }
        }
        $max_len      = length($language) if length($language) > $max_len;
    }
    my $column_1_offset = 0;
       $column_1_offset = $max_len - 17 if $max_len > 17;
    $elapsed_sec = 0.5 unless $elapsed_sec;

    my $spacing_0 = 23;
    my $spacing_1 = 13;
    my $spacing_2 =  9;
    my $spacing_3 = 17;
    if (!$opt_3) {
        $spacing_1 = 19;
        $spacing_2 = 14;
        $spacing_3 = 28;
    }
    $spacing_0 += $column_1_offset;
    $spacing_1 += $column_1_offset;
    $spacing_3 += $column_1_offset;
    my %Format = (
        '1' => { 'xml' => 'name="%s" ',
                 'txt' => "\%-${spacing_0}s ",
               },
        '2' => { 'xml' => 'name="%s" ',
                 'txt' => "\%-${spacing_3}s ",
               },
        '3' => { 'xml' => 'files_count="%d" ',
                 'txt' => '%5d ',
               },
        '4' => { 'xml' => 'blank="%d" comment="%d" code="%d" ',
                 'txt' => "\%${spacing_2}d \%${spacing_2}d \%${spacing_2}d",
               },
        '5' => { 'xml' => 'factor="%.2f" scaled="%.2f" ',
                 'txt' => ' x %6.2f = %14.2f',
               },
    );
    my $Style = "txt";
       $Style = "xml" if $opt_xml ;
       $Style = "xml" if $opt_yaml;  # not a typo; just set to anything but txt
       $Style = "xml" if $opt_csv ;  # not a typo; just set to anything but txt

    my $hyphen_line = sprintf "%s", '-' x (79 + $column_1_offset);
       $hyphen_line = sprintf "%s", '-' x (68 + $column_1_offset) 
            if (!$opt_3) and (68 + $column_1_offset) > 79;
    my $data_line  = "";
    my $first_column;
    my $BY_LANGUAGE = 0;
    my $BY_FILE     = 0;
    if      ($report_type eq "by language") {
        $first_column = "Language";
        $BY_LANGUAGE  = 1;
    } elsif ($report_type eq "by file")     {
        $first_column = "File";
        $BY_FILE      = 1;
    } else {
        $first_column = "Report File";
    }

    my $header_line  = sprintf "%s v %4.2f", $URL, $version;
    my $sum_files    = 1;
    my $sum_lines    = 1;
       $header_line .= sprintf("  T=%.1f s (%.1f files/s, %.1f lines/s)",
                        $elapsed_sec           ,
                        $sum_files/$elapsed_sec,
                        $sum_lines/$elapsed_sec) unless $opt_sum_reports;
    if ($Style eq "txt") {
        push @results, output_header($header_line, $hyphen_line, $BY_FILE);
    } elsif ($Style eq "csv") {
        die "csv";
    }

    # column headers
    if (!$opt_3 and $BY_FILE) {
        my $spacing_n = $spacing_1 - 11;
        $data_line  = sprintf "%-${spacing_n}s" , $first_column;
    } else {
        $data_line  = sprintf "%-${spacing_1}s ", $first_column;
    }
    if ($BY_FILE) {
        $data_line .= sprintf "%${spacing_2}s"   , ""     ;
    } else {
        $data_line .= sprintf "%${spacing_2}s "  , "files";
    }
    $data_line .= sprintf "%${spacing_2}s %${spacing_2}s %${spacing_2}s",
        "blank"         ,
        "comment"       ,
        "code";

    if ($Style eq "txt") {
        push @results, $data_line;
        push @results, $hyphen_line;
    }

    foreach my $lang_or_file (sort {
                                 $rhhh_count->{$b}{'code'} <=>
                                 $rhhh_count->{$a}{'code'}
                               }
                          keys %{$rhhh_count}) {

        push @results, "$lang_or_file";
        foreach my $S (qw(same modified added removed)) {
            my $indent = $spacing_1 - 2;
            my $line .= sprintf " %-${indent}s", $S;
            if ($BY_FILE) {
                $line .= sprintf "   ";
            } else {
                $line .= sprintf "  %${spacing_2}s", $rhhh_count->{$lang_or_file}{'nFiles'}{$S};
            }
            $line .= sprintf " %${spacing_2}s %${spacing_2}s %${spacing_2}s",
                $rhhh_count->{$lang_or_file}{'blank'}{$S}   ,
                $rhhh_count->{$lang_or_file}{'comment'}{$S} ,
                $rhhh_count->{$lang_or_file}{'code'}{$S}    ;
            push @results, $line;
        }
    }
    push @results, "-" x 79;
    push @results, "SUM:";
    foreach my $S (qw(same modified added removed)) {
        my $indent = $spacing_1 - 2;
        my $line .= sprintf " %-${indent}s", $S;
            if ($BY_FILE) {
                $line .= sprintf "   ";
            } else {
                $line .= sprintf "  %${spacing_2}s", $sum{'nFiles'}{$S};
            }
        $line .= sprintf " %${spacing_2}s %${spacing_2}s %${spacing_2}s",
            $sum{'blank'}{$S}   ,
            $sum{'comment'}{$S} ,
            $sum{'code'}{$S}    ;
        push @results, $line;
    }
    push @results, "-" x 79;
    write_xsl_file() if $opt_xsl and $opt_xsl eq $CLOC_XSL;
    print "<- diff_report\n" if $opt_v > 2;

    return @results;
} # 1}}}
sub xml_or_yaml_header {                     # {{{1
    my ($URL, $version, $elapsed_sec, $sum_files, $sum_lines) = @_;
    my $header      = "";
    my $file_rate   = $sum_files/$elapsed_sec;
    my $line_rate   = $sum_lines/$elapsed_sec;
    my $type        = ""; 
       $type        = "diff_" if $opt_diff;
    my $report_file = "";
       $report_file = "  <report_file>$opt_report_file</report_file>"
       if $opt_report_file;
    if ($opt_xml) {
        $header = "<?xml version=\"1.0\"?>";
        $header .= "\n<?xml-stylesheet type=\"text/xsl\" href=\"" . $opt_xsl . "\"?>" if $opt_xsl;
        $header .= "<${type}results>
<header>
  <cloc_url>$URL</cloc_url>
  <cloc_version>$version</cloc_version>
  <elapsed_seconds>$elapsed_sec</elapsed_seconds>
  <n_files>$sum_files</n_files>
  <n_lines>$sum_lines</n_lines>
  <files_per_second>$file_rate</files_per_second>
  <lines_per_second>$line_rate</lines_per_second>";
        $header .= "\n$report_file"
            if $opt_report_file;
        $header .= "\n</header>";
    } elsif ($opt_yaml) {
        $header = "---\n# $URL
header :
  cloc_url           : http://cloc.sourceforge.net
  cloc_version       : $version
  elapsed_seconds    : $elapsed_sec
  n_files            : $sum_files
  n_lines            : $sum_lines
  files_per_second   : $file_rate
  lines_per_second   : $line_rate";
        $header .= "\n  report_file        : $opt_report_file"
            if $opt_report_file;
    }
    return $header;
} # 1}}}
sub diff_xml_yaml_report {                   # {{{1
    # returns an array of lines containing the results
    my ($version    , # in
        $elapsed_sec, # in
        $report_type, # in  "by language" | "by report file" | "by file"
        $rhhh_count , # in  count{TYPE}{nFiles|code|blank|comment}{a|m|r|s}
        $rh_scale   , # in
       ) = @_;
    print "-> diff_xml_yaml_report\n" if $opt_v > 2;

#print "diff_report: ", Dumper($rhhh_count), "\n";
    my @results       = ();
    
    my $languages     = ();
    my %sum           = (); # sum{nFiles|blank|comment|code}{same|modified|added|removed}

    my $sum_files = 0;
    my $sum_lines = 0;
    foreach my $language (keys %{$rhhh_count}) {
        foreach my $V (qw(nFiles blank comment code)) {
            foreach my $S (qw(added same modified removed)) {
                $rhhh_count->{$language}{$V}{$S} = 0 unless
                    defined $rhhh_count->{$language}{$V}{$S};
                $sum{$V}{$S}  += $rhhh_count->{$language}{$V}{$S};
                if ($V eq "nFiles") {
                    $sum_files += $rhhh_count->{$language}{$V}{$S};
                } else {
                    $sum_lines += $rhhh_count->{$language}{$V}{$S};
                }
            }
        }
    }
    $elapsed_sec = 0.5 unless $elapsed_sec;

    my $data_line   = "";
    my $BY_LANGUAGE = 0;
    my $BY_FILE     = 0;
    if      ($report_type eq "by language") {
        $BY_LANGUAGE  = 1;
    } elsif ($report_type eq "by file")     {
        $BY_FILE      = 1;
    }

    if (!$ALREADY_SHOWED_HEADER) {
        push @results,
              xml_or_yaml_header($URL, $version, $elapsed_sec, 
                                 $sum_files, $sum_lines);
        $ALREADY_SHOWED_HEADER = 1;
    }

    foreach my $S (qw(same modified added removed)) {
        if ($opt_xml) {
            push @results, "  <$S>";
        } elsif ($opt_yaml) {
            push @results, "$S :";
        }
        foreach my $lang_or_file (sort {
                                     $rhhh_count->{$b}{'code'} <=>
                                     $rhhh_count->{$a}{'code'}
                                   }
                              keys %{$rhhh_count}) {
            my $L = "";
            if ($opt_xml) {
                if ($BY_FILE) {
                    $L .= sprintf "    <file name=\"%s\" files_count=\"1\" ", 
                            $lang_or_file;
                } else {
                    $L .= sprintf "    <language name=\"%s\" files_count=\"%d\" ",
                            $lang_or_file ,
                            $rhhh_count->{$lang_or_file}{'nFiles'}{$S};
                }
                foreach my $T (qw(blank comment code)) {
                    $L .= sprintf "%s=\"%d\" ", 
                            $T, $rhhh_count->{$lang_or_file}{$T}{$S};
                }
                push @results, $L . "/>";
            } elsif ($opt_yaml) {
                if ($BY_FILE) {
                    push @results, sprintf "  - file : %s", $lang_or_file;
                    push @results, sprintf "    files_count : 1", 
                } else {
                    push @results, sprintf "  - language : %s", $lang_or_file;
                    push @results, sprintf "    files_count : %d", 
                            $rhhh_count->{$lang_or_file}{'nFiles'}{$S};
                }
                foreach my $T (qw(blank comment code)) {
                    push @results, sprintf "    %s : %d", 
                            $T, $rhhh_count->{$lang_or_file}{$T}{$S};
                }
            }
        }

        if ($opt_xml) {
            my $L = sprintf "    <total sum_files=\"%d\" ", $sum{'nFiles'}{$S};
            foreach my $V (qw(blank comment code)) {
                $L .= sprintf "%s=\"%d\" ", $V, $sum{$V}{$S};
            }
            push @results, $L . "/>";
            push @results, "  </$S>";
        } elsif ($opt_yaml) {
            push @results, sprintf "%s_total :\n    sum_files : %d", 
                                $S, $sum{'nFiles'}{$S};
            foreach my $V (qw(blank comment code)) {
                push @results, sprintf "    %s : %d", $V, $sum{$V}{$S};
            }
        }
    }

    if ($opt_xml) {
        push @results, "</diff_results>";
    }
    write_xsl_file() if $opt_xsl and $opt_xsl eq $CLOC_XSL;
    print "<- diff_xml_yaml_report\n" if $opt_v > 2;
    return @results;
} # 1}}}
sub diff_csv_report {                        # {{{1
    # returns an array of lines containing the results
    my ($version    , # in
        $elapsed_sec, # in
        $report_type, # in  "by language" | "by report file" | "by file"
        $rhhh_count , # in  count{TYPE}{nFiles|code|blank|comment}{a|m|r|s}
        $rh_scale   , # in  unused
       ) = @_;
    print "-> diff_csv_report\n" if $opt_v > 2;

#use Data::Dumper;
#print "diff_csv_report: ", Dumper($rhhh_count), "\n";
#die;
    my @results       = ();
    my $languages     = ();

    my $data_line   = "";
    my $BY_LANGUAGE = 0;
    my $BY_FILE     = 0;
    if      ($report_type eq "by language") {
        $BY_LANGUAGE  = 1;
    } elsif ($report_type eq "by file")     {
        $BY_FILE      = 1;
    }

    $elapsed_sec = 0.5 unless $elapsed_sec;

    my $line = "Language, ";
       $line = "File, " if $BY_FILE;
    foreach my $item (qw(files blank comment code)) {
        next if $BY_FILE and $item eq 'files';
        foreach my $symbol qw( == != + - ) {
            $line .= "$symbol $item, ";
        }
    }
    $line .= "\"$URL v $version T=$elapsed_sec s\"";
    push @results, $line;

    foreach my $lang_or_file (sort {
                                 $rhhh_count->{$b}{'code'} <=>
                                 $rhhh_count->{$a}{'code'}
                               }
                          keys %{$rhhh_count}) {
        $line = "$lang_or_file, ";
        foreach my $item (qw(nFiles blank comment code)) {
            next if $BY_FILE and $item eq 'nFiles';
            foreach my $symbol (qw(same modified added removed)) {
                if (defined $rhhh_count->{$lang_or_file}{$item}{$symbol}) {
                    $line .= "$rhhh_count->{$lang_or_file}{$item}{$symbol}, ";
                } else {
                    $line .= "0, ";
                }
            }
        }
        push @results, $line;
    }

    print "<- diff_csv_report\n" if $opt_v > 2;
    return @results;
} # 1}}}
sub generate_sql    {                        # {{{1
    my ($elapsed_sec, # in
        $rhh_count  , # in  count{TYPE}{lang|code|blank|comment|scaled}
        $rh_scale   , # in
       ) = @_;
    print "-> generate_sql\n" if $opt_v > 2;

    $opt_sql_project = cwd() unless defined $opt_sql_project;
    $opt_sql_project =~ s{/}{\\}g if $ON_WINDOWS;

    my $schema = "
create table metadata (          -- $URL v $VERSION
                timestamp text,    
                Project   text,    
                elapsed_s real);   
create table t        (
                Project   text   ,  
                Language  text   ,  
                File      text   ,  
                nBlank    integer,  
                nComment  integer,  
                nCode     integer,  
                nScaled   real   ); 
";
    $opt_sql = "-" if $opt_sql eq "1";

    my $open_mode = ">";
       $open_mode = ">>" if $opt_sql_append;

    my $fh = new IO::File; # $opt_sql, "w";
    if (!$fh->open("${open_mode}${opt_sql}")) {
        die "Unable to write to $opt_sql  $!\n";
    }
    print $fh $schema unless defined $opt_sql_append;

    print $fh "begin transaction;\n";
    printf $fh "insert into metadata values('%s', '%s', %f);\n",
                strftime("%Y-%m-%d %H:%M:%S", localtime(time())),
                $opt_sql_project, $elapsed_sec;

    my $nIns = 0;
    foreach my $file (keys %{$rhh_count}) {
        my $language = $rhh_count->{$file}{'lang'};
        my $clean_filename = $file;
        # If necessary (that is, if the input contained an
        # archive file [.tar.gz, etc]), strip the temporary
        # directory name which was used to expand the archive
        # from the file name.
        foreach my $temp_d (keys %TEMP_DIR) {
            if ($ON_WINDOWS) {
            # \ -> / necessary to allow the next if test's
            # m{} to work in the presence of spaces in file names
                $temp_d         =~ s{\\}{/}g;
                $clean_filename =~ s{\\}{/}g;
            }
            if ($clean_filename =~ m{^$temp_d/}) {
                $clean_filename =~ s{^$temp_d/}{};
                last;
            }
        }
        $clean_filename =~ s{/}{\\}g if $ON_WINDOWS; # then go back from / to \
        printf $fh "insert into t values('%s', '%s', '%s', %d, %d, %d, %f);\n",
                    $opt_sql_project           ,
                    $language                  ,
                    $clean_filename            ,
                    $rhh_count->{$file}{'blank'},
                    $rhh_count->{$file}{'comment'},
                    $rhh_count->{$file}{'code'}   ,
                    $rhh_count->{$file}{'code'}*$rh_scale->{$language};
        ++$nIns;
        if (!($nIns % 10_000)) {
            print $fh "commit;\n";
            print $fh "begin transaction;\n";
        }
    }
    print $fh "commit;\n";

    $fh->close unless $opt_sql eq "-"; # don't try to close STDOUT
    print "<- generate_sql\n" if $opt_v > 2;

    # sample query:
    #
    #   select project, language, 
    #          sum(nCode)     as Code, 
    #          sum(nComment)  as Comments, 
    #          sum(nBlank)    as Blank,  
    #          sum(nCode)+sum(nComment)+sum(nBlank) as All_Lines,
    #          100.0*sum(nComment)/(sum(nCode)+sum(nComment)) as Comment_Pct
    #          from t group by Project, Language order by Project, Code desc;
    #
} # 1}}}
sub output_header   {                        # {{{1
    my ($header_line, 
        $hyphen_line,
        $BY_FILE    ,)    = @_;
    print "-> output_header\n" if $opt_v > 2;
    my @R = ();
    if      ($opt_xml) {
        if (!$ALREADY_SHOWED_XML_SECTION) {
            push @R, "<?xml version=\"1.0\"?>";
            push @R, '<?xml-stylesheet type="text/xsl" href="' .
                            $opt_xsl . '"?>' if $opt_xsl;
            push @R, "<results>";
            push @R, "<header>$header_line</header>";
            $ALREADY_SHOWED_XML_SECTION = 1;
        }
        if ($BY_FILE) {
            push @R, "<files>";
        } else {
            push @R, "<languages>";
        }
    } elsif ($opt_yaml) {
        push @R, "---\n# $header_line";
    } elsif ($opt_csv) {
        # append the header to the end of the column headers
        # to keep the output a bit cleaner from a spreadsheet
        # perspective
    } else {
        if ($ALREADY_SHOWED_HEADER) {
            push @R, "";
        } else {
            push @R, $header_line;
            $ALREADY_SHOWED_HEADER = 1;
        }
        push @R, $hyphen_line;
    }
    print "<- output_header\n" if $opt_v > 2;
    return @R;
} # 1}}}
sub generate_report {                        # {{{1
    # returns an array of lines containing the results
    my ($version    , # in
        $elapsed_sec, # in
        $report_type, # in  "by language" | "by report file" | "by file"
        $rhh_count  , # in  count{TYPE}{nFiles|code|blank|comment|scaled}
        $rh_scale   , # in
       ) = @_;

    print "-> generate_report\n" if $opt_v > 2;
    my @results       = ();
    
    my $languages     = ();

    my $sum_files     = 0;
    my $sum_code      = 0;
    my $sum_blank     = 0;
    my $sum_comment   = 0;
    my $max_len       = 0;
    foreach my $language (keys %{$rhh_count}) {
        $sum_files   += $rhh_count->{$language}{'nFiles'} ;
        $sum_blank   += $rhh_count->{$language}{'blank'}  ;
        $sum_comment += $rhh_count->{$language}{'comment'};
        $sum_code    += $rhh_count->{$language}{'code'}   ;
        $max_len      = length($language) if length($language) > $max_len;
    }
    my $column_1_offset = 0;
       $column_1_offset = $max_len - 17 if $max_len > 17;
    my $sum_lines = $sum_blank + $sum_comment + $sum_code;
    $elapsed_sec = 0.5 unless $elapsed_sec;

    my $spacing_0 = 23;
    my $spacing_1 = 13;
    my $spacing_2 =  9;
    my $spacing_3 = 17;
    if (!$opt_3) {
        $spacing_1 = 19;
        $spacing_2 = 14;
        $spacing_3 = 28;
    }
    $spacing_0 += $column_1_offset;
    $spacing_1 += $column_1_offset;
    $spacing_3 += $column_1_offset;
    my %Format = (
        '1' => { 'xml' => 'name="%s" ',
                 'txt' => "\%-${spacing_0}s ",
               },
        '2' => { 'xml' => 'name="%s" ',
                 'txt' => "\%-${spacing_3}s ",
               },
        '3' => { 'xml' => 'files_count="%d" ',
                 'txt' => '%5d ',
               },
        '4' => { 'xml' => 'blank="%d" comment="%d" code="%d" ',
                 'txt' => "\%${spacing_2}d \%${spacing_2}d \%${spacing_2}d",
               },
        '5' => { 'xml' => 'factor="%.2f" scaled="%.2f" ',
                 'txt' => ' x %6.2f = %14.2f',
               },
    );
    my $Style = "txt";
       $Style = "xml" if $opt_xml ;
       $Style = "xml" if $opt_yaml;  # not a typo; just set to anything but txt
       $Style = "xml" if $opt_csv ;  # not a typo; just set to anything but txt

    my $hyphen_line = sprintf "%s", '-' x (79 + $column_1_offset);
       $hyphen_line = sprintf "%s", '-' x (68 + $column_1_offset) 
            if (!$opt_3) and (68 + $column_1_offset) > 79;
    my $data_line  = "";
    my $first_column;
    my $BY_LANGUAGE = 0;
    my $BY_FILE     = 0;
    if      ($report_type eq "by language") {
        $first_column = "Language";
        $BY_LANGUAGE  = 1;
    } elsif ($report_type eq "by file")     {
        $first_column = "File";
        $BY_FILE      = 1;
    } else {
        $first_column = "Report File";
    }

    my $header_line  = sprintf "%s v %4.2f", $URL, $version;
       $header_line .= sprintf("  T=%.1f s (%.1f files/s, %.1f lines/s)",
                        $elapsed_sec           ,
                        $sum_files/$elapsed_sec,
                        $sum_lines/$elapsed_sec) unless $opt_sum_reports;
    if ($opt_xml or $opt_yaml) {
        if (!$ALREADY_SHOWED_HEADER) {
            push @results, xml_or_yaml_header($URL, $version, $elapsed_sec, 
                                              $sum_files, $sum_lines);
            $ALREADY_SHOWED_HEADER = 1;
        }
        if ($BY_FILE) {
            push @results, "<files>";
        } else {
            push @results, "<languages>";
        }
    } else {
        push @results, output_header($header_line, $hyphen_line, $BY_FILE);
    }

    if ($Style eq "txt") {
        # column headers
        if (!$opt_3 and $BY_FILE) {
            my $spacing_n = $spacing_1 - 11;
            $data_line  = sprintf "%-${spacing_n}s ", $first_column;
        } else {
            $data_line  = sprintf "%-${spacing_1}s ", $first_column;
        }
        if ($BY_FILE) {
            $data_line .= sprintf "%${spacing_2}s "  , " "    ;
        } else {
            $data_line .= sprintf "%${spacing_2}s "  , "files";
        }
        $data_line .= sprintf "%${spacing_2}s %${spacing_2}s %${spacing_2}s",
            "blank"         ,
            "comment"       ,
            "code";
        $data_line .= sprintf " %8s   %14s",
            "scale"         ,
            "3rd gen. equiv"
              if $opt_3;
        push @results, $data_line;
        push @results, $hyphen_line;
    }
    if ($opt_csv) {
        my $header2;
        if ($BY_FILE) {
            $header2 = "language,filename";
        } else {
            $header2 = "files,language";
        }
        $header2 .= ",blank,comment,code";
        $header2 .= ",scale,3rd gen. equiv" if $opt_3;
        $header2 .= ',"' . $header_line . '"';
        push @results, $header2;
    }

    my $sum_scaled = 0;
    foreach my $lang_or_file (sort {
                                 $rhh_count->{$b}{'code'} <=>
                                 $rhh_count->{$a}{'code'}
                               }
                          keys %{$rhh_count}) {
        my ($factor, $scaled);
        if ($BY_LANGUAGE or $BY_FILE) {
            $factor = 1;
            if ($BY_LANGUAGE) {
                if (defined $rh_scale->{$lang_or_file}) {
                    $factor = $rh_scale->{$lang_or_file};
                } else {
                    warn "No scale factor for $lang_or_file; using 1.00";
                }
            } else { # by individual code file
                $factor = $rh_scale->{$rhh_count->{$lang_or_file}{'lang'}};
            }
            $scaled = $factor*$rhh_count->{$lang_or_file}{'code'};
        } else {
            if (!defined $rhh_count->{$lang_or_file}{'scaled'}) {
                $opt_3 = 0;
                # If we're summing together files previously generated
                # with --no3 then rhh_count->{$lang_or_file}{'scaled'}
                # this variable will be undefined.  That should only
                # happen when summing together by file however.
            } elsif ($BY_LANGUAGE) {
                warn "Missing scaled language info for $lang_or_file\n";
            }
            if ($opt_3) {
                $scaled =         $rhh_count->{$lang_or_file}{'scaled'};
                $factor = $scaled/$rhh_count->{$lang_or_file}{'code'};
            }
        }

        if ($BY_FILE) {
            $data_line  = sprintf $Format{'1'}{$Style}, $lang_or_file;
        } else {
            $data_line  = sprintf $Format{'2'}{$Style}, $lang_or_file;
        }
        $data_line .= sprintf $Format{3}{$Style}  , 
                        $rhh_count->{$lang_or_file}{'nFiles'} unless $BY_FILE;
        $data_line .= sprintf $Format{4}{$Style}  , 
            $rhh_count->{$lang_or_file}{'blank'}  ,
            $rhh_count->{$lang_or_file}{'comment'},
            $rhh_count->{$lang_or_file}{'code'}   ;
        $data_line .= sprintf $Format{5}{$Style}  ,
            $factor                               ,
            $scaled if $opt_3;
        $sum_scaled  += $scaled if $opt_3;

        if ($opt_xml) {
            if (defined $rhh_count->{$lang_or_file}{'lang'}) {
                my $lang = $rhh_count->{$lang_or_file}{'lang'};
                if (!defined $languages->{$lang}) {
                    $languages->{$lang} = $lang;
                }
                $data_line.=' language="' . $lang . '" ';
            }
            if ($BY_FILE) {
                push @results, "  <file " . $data_line . "/>";
            } else {
                push @results, "  <language " . $data_line . "/>";
            }
        } elsif ($opt_yaml) {
            push @results,$lang_or_file . ":";
            push @results,"  nFiles: "  .$rhh_count->{$lang_or_file}{'nFiles'} 
                unless $BY_FILE;
            push @results,"  blank: "   .$rhh_count->{$lang_or_file}{'blank'}  ;
            push @results,"  comment: " .$rhh_count->{$lang_or_file}{'comment'};
            push @results,"  code: "    .$rhh_count->{$lang_or_file}{'code'}   ;
            push @results,"  language: ".$rhh_count->{$lang_or_file}{'lang'} 
                if $BY_FILE;
            if ($opt_3) {
                push @results, "  scaled: " . $scaled;
                push @results, "  factor: " . $factor;
            }
        } elsif ($opt_csv) {
            my $extra_3 = "";
               $extra_3 = ",$factor,$scaled" if $opt_3;
            my $str;
            if ($BY_FILE) {
                $str = $rhh_count->{$lang_or_file}{'lang'}   . ",";
            } else {
                $str = $rhh_count->{$lang_or_file}{'nFiles'} . ",";
            }
            $str .= $lang_or_file                         . "," .
                    $rhh_count->{$lang_or_file}{'blank'}  . "," .
                    $rhh_count->{$lang_or_file}{'comment'}. "," .
                    $rhh_count->{$lang_or_file}{'code'}         .
                    $extra_3;
            push @results, $str;
        } else {
            push @results, $data_line;
        }
    }

    my $avg_scale = 1;  # weighted average of scale factors
       $avg_scale = sprintf("%.2f", $sum_scaled / $sum_code) 
            if $sum_code and $opt_3;

    if ($opt_xml) {
        $data_line = "";
        if (!$BY_FILE) {
            $data_line .= sprintf "sum_files=\"%d\" ", $sum_files;
        }
        $data_line .= sprintf $Format{'4'}{$Style},
            $sum_blank   ,
            $sum_comment ,
            $sum_code    ;
        $data_line .= sprintf $Format{'5'}{$Style},
            $avg_scale   ,
            $sum_scaled  if $opt_3;
        push @results, "  <total " . $data_line . "/>";

        if ($BY_FILE) {
            push @results, "</files>";
        } else {
            foreach my $language (keys %{$languages}) {
                push @results, '  <language name="' . $language . '"/>';
            }
            push @results, "</languages>";
        }

        if (!$opt_by_file_by_lang or $ALREADY_SHOWED_XML_SECTION) {
    	    push @results, "</results>";
        } else {
            $ALREADY_SHOWED_XML_SECTION = 1;
        }
    } elsif ($opt_yaml) {
        push @results, "SUM:";
        push @results, "  blank: "  . $sum_blank  ;
        push @results, "  code: "   . $sum_code   ;
        push @results, "  comment: ". $sum_comment;
        push @results, "  nFiles: " . $sum_files  ;
        if ($opt_3) {
            push @results, "  scaled: " . $sum_scaled;
            push @results, "  factor: " . $avg_scale ;
        }
    } elsif ($opt_csv) {
        # do nothing
    } else {

        if ($BY_FILE) {
            $data_line  = sprintf "%-${spacing_0}s ", "SUM:"  ;
        } else {
            $data_line  = sprintf "%-${spacing_1}s ", "SUM:"  ;
            $data_line .= sprintf "%${spacing_2}d ", $sum_files;
        }
        $data_line .= sprintf $Format{'4'}{$Style},
            $sum_blank   ,
            $sum_comment ,
            $sum_code    ;
        $data_line .= sprintf $Format{'5'}{$Style},
            $avg_scale   ,
            $sum_scaled if $opt_3;
        push @results, $hyphen_line if $sum_files > 1 or $opt_sum_one;
        push @results, $data_line   if $sum_files > 1 or $opt_sum_one;
        push @results, $hyphen_line;
    }
    write_xsl_file() if $opt_xsl and $opt_xsl eq $CLOC_XSL;
    print "<- generate_report\n" if $opt_v > 2;
    return @results;
} # 1}}}
sub print_errors {                           # {{{1
    my ($rh_Error_Codes, # in
        $raa_errors    , # in
       ) = @_;

    print "-> print_errors\n" if $opt_v > 2;
    my %error_string = reverse(%{$rh_Error_Codes});
    my $nErrors      = scalar @{$raa_errors};
    warn sprintf "\n%d error%s:\n", plural_form(scalar @Errors);
    for (my $i = 0; $i < $nErrors; $i++) {
        warn sprintf "%s:  %s\n", 
                     $error_string{ $raa_errors->[$i][0] },
                     $raa_errors->[$i][1] ;
    }
    print "<- print_errors\n" if $opt_v > 2;

} # 1}}}
sub write_lang_def {                         # {{{1
    my ($file                     ,
        $rh_Language_by_Extension , # in
        $rh_Language_by_Script    , # in
        $rh_Language_by_File      , # in
        $rhaa_Filters_by_Language , # in
        $rh_Not_Code_Extension    , # in
        $rh_Not_Code_Filename     , # in
        $rh_Scale_Factor          , # in
        $rh_EOL_Continuation_re   , # in
       ) = @_;

    print "-> write_lang_def($file)\n" if $opt_v > 2;
    my $OUT = new IO::File $file, "w";
    die "Unable to write to $file\n" unless defined $OUT;

    foreach my $language (sort keys %{$rhaa_Filters_by_Language}) {
        next if $language eq "MATLAB/Objective C/MUMPS" or
                $language eq "PHP/Pascal";
        printf $OUT "%s\n", $language;
        foreach my $filter (@{$rhaa_Filters_by_Language->{$language}}) {
            printf $OUT "    filter %s", $filter->[0];
            printf $OUT " %s", $filter->[1] if defined $filter->[1];
            print  $OUT "\n";
        }
        foreach my $ext (sort keys %{$rh_Language_by_Extension}) {
            if ($language eq $rh_Language_by_Extension->{$ext}) {
                printf $OUT "    extension %s\n", $ext;
            }
        }
        foreach my $filename (sort keys %{$rh_Language_by_File}) {
            if ($language eq $rh_Language_by_File->{$filename}) {
                printf $OUT "    filename %s\n", $filename;
            }
        }
        foreach my $script_exe (sort keys %{$rh_Language_by_Script}) {
            if ($language eq $rh_Language_by_Script->{$script_exe}) {
                printf $OUT "    script_exe %s\n", $script_exe;
            }
        }
        printf $OUT "    3rd_gen_scale %.2f\n", $rh_Scale_Factor->{$language};
        if (defined $rh_EOL_Continuation_re->{$language}) {
            printf $OUT "    end_of_line_continuation %s\n", 
                $rh_EOL_Continuation_re->{$language};
        }
    }

    $OUT->close;
    print "<- write_lang_def\n" if $opt_v > 2;
} # 1}}}
sub read_lang_def {                          # {{{1
    my ($file                     ,
        $rh_Language_by_Extension , # out
        $rh_Language_by_Script    , # out
        $rh_Language_by_File      , # out
        $rhaa_Filters_by_Language , # out
        $rh_Not_Code_Extension    , # out
        $rh_Not_Code_Filename     , # out
        $rh_Scale_Factor          , # out
        $rh_EOL_Continuation_re   , # out
        $rh_EOL_abc,
       ) = @_;


    print "-> read_lang_def($file)\n" if $opt_v > 2;
    my $IN = new IO::File $file, "r";
    die "Unable to read $file.\n" unless defined $IN;

    my $language = "";
    while (<$IN>) {
        next if /^\s*#/ or /^\s*$/;

        if (/^(\w+.*?)\s*$/) {
            $language = $1;
            next;
        }
        die "Missing computer language name, line $. of $file\n"
            unless $language;

        if      (/^    filter\s+(\w+)\s*$/) {
            push @{$rhaa_Filters_by_Language->{$language}}, [ $1 ]

        } elsif (/^    filter\s+(\w+)\s+(.*?)\s*$/) {
            push @{$rhaa_Filters_by_Language->{$language}}, [ $1 , $2 ]

        } elsif (/^    extension\s+(\S+)\s*$/) {
            if (defined $rh_Language_by_Extension->{$1}) {
                die "File extension collision:  $1 ",
                    "maps to languages '$rh_Language_by_Extension->{$1}' ",
                    "and '$language'\n" ,
                    "Edit $file and remove $1 from one of these two ",
                    "language definitions.\n";
            }
            $rh_Language_by_Extension->{$1} = $language;

        } elsif (/^    filename\s+(\S+)\s*$/) {
            $rh_Language_by_File->{$1} = $language;

        } elsif (/^    script_exe\s+(\S+)\s*$/) {
            $rh_Language_by_Script->{$1} = $language;

        } elsif (/^    3rd_gen_scale\s+(\S+)\s*$/) {
            $rh_Scale_Factor->{$language} = $1;

        } elsif (/^    end_of_line_continuation\s+(\S+)\s*$/) {
            $rh_EOL_Continuation_re->{$language} = $1;

        } else {
            die "Unexpected data line $. of $file:\n$_\n";
        }

    }
    $IN->close;
    print "<- read_lang_def\n" if $opt_v > 2;
} # 1}}}
sub print_extension_info {                   # {{{1
    my ($extension,) = @_;
    if ($extension) {  # show information on this extension
        foreach my $ext (sort {lc $a cmp lc $b } keys %Language_by_Extension) {
            # Language_by_Extension{f}    = 'Fortran 77' 
            printf "%-12s -> %s\n", $ext, $Language_by_Extension{$ext}
                if $ext =~ m{$extension}i;
        }
    } else {           # show information on all  extensions
        foreach my $ext (sort {lc $a cmp lc $b } keys %Language_by_Extension) {
            # Language_by_Extension{f}    = 'Fortran 77' 
            printf "%-12s -> %s\n", $ext, $Language_by_Extension{$ext};
        }
    }
} # 1}}}
sub print_language_info {                    # {{{1
    my ($language,) = @_;
    my %extensions = (); # the subset matched by the given $language value
    if ($language) {  # show information on this language
        foreach my $ext (sort {lc $a cmp lc $b } keys %Language_by_Extension) {
            # Language_by_Extension{f}    = 'Fortran 77' 
            push @{$extensions{$Language_by_Extension{$ext}} }, $ext
                if $Language_by_Extension{$ext} =~ m{$language}i;
        }
    } else {          # show information on all  languages
        foreach my $ext (sort {lc $a cmp lc $b } keys %Language_by_Extension) {
            # Language_by_Extension{f}    = 'Fortran 77' 
            push @{$extensions{$Language_by_Extension{$ext}} }, $ext
        }
    }

    # add exceptions (one file extension mapping to multiple languages)
    if (!$language or 
        $language =~ /^(Objective C|MATLAB|MUMPS)$/i) {
        push @{$extensions{'Objective C'}}, "m";
        push @{$extensions{'MATLAB'}}     , "m";
        push @{$extensions{'MUMPS'}}      , "m";
        delete $extensions{'MATLAB/Objective C/MUMPS'};
    }

    if (%extensions) {
        foreach my $lang (sort {lc $a cmp lc $b } keys %extensions) {
            printf "%-26s (%s)\n", $lang, join(", ", @{$extensions{$lang}});
        }
    }
} # 1}}}
sub make_file_list {                         # {{{1
    my ($ra_arg_list,  # in   file and/or directory names to examine
        $rh_Err     ,  # in   hash of error codes
        $raa_errors ,  # out  errors encountered
        $rh_ignored ,  # out  files not recognized as computer languages
        ) = @_;
    print "-> make_file_list(@{$ra_arg_list})\n" if $opt_v > 2;

    my ($fh, $filename);
    if ($opt_categorized) {
        $filename = $opt_categorized;
        $fh = new IO::File $filename, "+>";  # open for read/write
        die "Unable to write to $filename:  $!\n" unless defined $fh;
    } elsif ($opt_sdir) {
        # write to the user-defined scratch directory
        $filename = $opt_sdir . '/cloc_file_list.txt';
        $fh = new IO::File $filename, "+>";  # open for read/write
        die "Unable to write to $filename:  $!\n" unless defined $fh;
    } else {
        # let File::Temp create a suitable temporary file
        ($fh, $filename) = tempfile(UNLINK => 1);  # delete file on exit
        print "Using temp file list [$filename]\n" if $opt_v;
    }

    my @dir_list = ();
    foreach my $file_or_dir (@{$ra_arg_list}) {
#print "make_file_list file_or_dir=$file_or_dir\n";
        my $size_in_bytes = 0;
        if (!-r $file_or_dir) {
            push @{$raa_errors}, [$rh_Err->{'Unable to read'} , $file_or_dir];
            next;
        }
        if (is_file($file_or_dir)) {
            if (!(-s $file_or_dir)) {   # 0 sized file, named pipe, socket 
                $rh_ignored->{$file_or_dir} = 'zero sized file';
                next;
            } elsif (-B $file_or_dir and !$opt_read_binary_files) { 
                # avoid binary files unless user insists on reading them
                if ($opt_unicode) {
                    # only ignore if not a Unicode file w/trivial 
                    # ASCII transliteration
                    if (!unicode_file($file_or_dir)) {
                        $rh_ignored->{$file_or_dir} = 'binary file';
                        next;
                    }
                } else {
                    $rh_ignored->{$file_or_dir} = 'binary file';
                    next;
                }
            }
            push @file_list, "$file_or_dir";
        } elsif (is_dir($file_or_dir)) {
            push @dir_list, $file_or_dir;
        } else {
            push @{$raa_errors}, [$rh_Err->{'Neither file nor directory'} , $file_or_dir];
            $rh_ignored->{$file_or_dir} = 'not file, not directory';
        }
    }
    foreach my $dir (@dir_list) {
#print "make_file_list dir=$dir\n";
        # populates global variable @file_list
        find({wanted => \&files, follow => $opt_follow_links }, $dir);  
    }
    $nFiles_Found = scalar @file_list;
    printf "%8d text file%s.\n", plural_form($nFiles_Found) unless $opt_quiet;
    write_file($opt_found, sort @file_list) if $opt_found;

    my $nFiles_Categorized = 0;
    foreach my $file (@file_list) {
        printf "classifying $file\n" if $opt_v > 2;

        my $basename = basename $file;
        if ($Not_Code_Filename{$basename}) {
            $rh_ignored->{$file} = "listed in " . '$' .
                "Not_Code_Filename{$basename}";
            next;
        } elsif ($basename =~ m{~$}) {
            $rh_ignored->{$file} = "temporary editor file";
            next;
        }

        my $size_in_bytes = (stat $file)[7];
        my $language      = "";
        if ($All_One_Language) {
            # user over-rode auto-language detection by using
            # --force-lang with just a language name (no extension)
            $language      = $All_One_Language;
        } else {
            $language      = classify_file($file      ,
                                           $rh_Err    ,
                                           $raa_errors,
                                           $rh_ignored);
        }
die  "make_file_list($file) undef size" unless defined $size_in_bytes;
die  "make_file_list($file) undef lang" unless defined $language;
        printf $fh "%d,%s,%s\n", $size_in_bytes, $language, $file;
        ++$nFiles_Categorized;
        #printf "classified %d files\n", $nFiles_Categorized 
        #    unless (!$opt_progress_rate or 
        #            ($nFiles_Categorized % $opt_progress_rate));
    }
    printf "classified %d files\r", $nFiles_Categorized 
        if !$opt_quiet and $nFiles_Categorized > 1;

    print "<- make_file_list()\n" if $opt_v > 2;

    return $fh;   # handle to the file containing the list of files to process
}  # 1}}}
sub remove_duplicate_files {                 # {{{1
    my ($fh                   , # in 
        $rh_Language          , # out
        $rh_unique_source_file, # out
        $rh_Err               , # in
        $raa_errors           , # out  errors encountered
        $rh_ignored           , # out
        ) = @_;

    # Check for duplicate files by comparing file sizes.
    # Where files are equally sized, compare their MD5 checksums.
    print "-> remove_duplicate_files\n" if $opt_v > 2;

    my $n = 0;
    my %files_by_size = (); # files_by_size{ # bytes } = [ list of files ]
    seek($fh, 0, 0); # rewind to beginning of the temp file
    while (<$fh>) {
        ++$n;
        my ($size_in_bytes, $language, $file) = split(/,/, $_, 3);
        chomp($file);
        $rh_Language->{$file} = $language;
        push @{$files_by_size{$size_in_bytes}}, $file;
        if ($opt_skip_uniqueness) {
            $rh_unique_source_file->{$file} = 1;
        }
    }
    return if $opt_skip_uniqueness;
    if ($opt_progress_rate and ($n > $opt_progress_rate)) {
        printf "Duplicate file check %d files (%d known unique)\r", 
            $n, scalar keys %files_by_size;
    }
    $n = 0;
    foreach my $bytes (sort {$a <=> $b} keys %files_by_size) {
        ++$n;
        printf "Unique: %8d files                                          \r",
            $n unless (!$opt_progress_rate or ($n % $opt_progress_rate));
        if (scalar @{$files_by_size{$bytes}} == 1) {
            # only one file is this big; must be unique
            $rh_unique_source_file->{$files_by_size{$bytes}[0]} = 1;
            next;
        } else {
#print "equally sized files: ",join(", ", @{$files_by_size{$bytes}}), "\n";
            foreach my $F (different_files(\@{$files_by_size{$bytes}},
                                            $rh_Err     ,
                                            $raa_errors ,
                                            $rh_ignored ) ) {
                $rh_unique_source_file->{$F} = 1;
            }
        }
    }
    print "<- remove_duplicate_files\n" if $opt_v > 2;
} # 1}}}
sub files {                                  # {{{1
    # invoked by File::Find's find()   Populates global variable @file_list
    if ($opt_exclude_dir or $opt_exclude_list_file) {
        my $return = 0;
        foreach my $skip_dir (keys %Exclude_Dir) {
            # File::Find::dir used to always start with / but
            # newer versions (1.13) no longer do; have to correct for this
            my $dir = $File::Find::dir;
               $dir = "./$dir" unless $dir =~ m{^/};
            if ($dir =~ m{/\Q$skip_dir\E(/|$)} ) {
                $Ignored{$File::Find::name} = "--exclude-dir=$skip_dir";
                $return = 1;
                last;
            }
        }
        return if $return;
    }
    my $Dir = cwd(); # not $File::Find::dir which just gives relative path
	if ($opt_match_f    ) {	return unless /$opt_match_f/;     }
    if ($opt_not_match_f) {	return if     /$opt_not_match_f/; }
	if ($opt_match_d    ) {	return unless $Dir =~ m{$opt_match_d}     }
    if ($opt_not_match_d) {	return if     $Dir =~ m{$opt_not_match_d} }

    my $nBytes = -s     $_ ;
    if (!$nBytes and $opt_v > 5) {
        printf "files(%s)  zero size\n", $File::Find::name;
    }
    return unless $nBytes  ; # attempting other tests w/pipe or socket will hang
    my $is_dir = is_dir($_);
    my $is_bin = -B     $_ ;
    printf "files(%s)  size=%d is_dir=%d  -B=%d\n",
        $File::Find::name, $nBytes, $is_dir, $is_bin if $opt_v > 5;
    $is_bin = 0 if $opt_unicode and unicode_file($_);
    $is_bin = 0 if $opt_read_binary_files;
    return if $is_dir or $is_bin;
    ++$nFiles_Found;
    printf "%8d files\r", $nFiles_Found 
        unless (!$opt_progress_rate or ($nFiles_Found % $opt_progress_rate));
    push @file_list, $File::Find::name;
} # 1}}}
sub archive_files {                          # {{{1
    # invoked by File::Find's find()  Populates global variable @binary_archive
    foreach my $ext (keys %Known_Binary_Archives) {
        push @binary_archive, $File::Find::name 
            if $File::Find::name =~ m{$ext$};
    }
} # 1}}}
sub is_file {                                # {{{1
    # portable method to test if item is a file
    # (-f doesn't work in ActiveState Perl on Windows)
    my $item = shift @_;

    if ($ON_WINDOWS) {
        my $mode = (stat $item)[2];
           $mode = 0 unless $mode;
        if ($mode & 0100000) { return 1; } 
        else                 { return 0; }
    } else {
        return (-f $item);  # works on Unix, Linux, CygWin, z/OS
    }
} # 1}}}
sub is_dir {                                 # {{{1
    # portable method to test if item is a directory
    # (-d doesn't work in ActiveState Perl on Windows)
    my $item = shift @_;

    if ($ON_WINDOWS) {
        my $mode = (stat $item)[2];
           $mode = 0 unless $mode;
        if ($mode & 0040000) { return 1; } 
        else                 { return 0; }
    } else {
        return (-d $item);  # works on Unix, Linux, CygWin, z/OS
    }
} # 1}}}
sub is_excluded {                            # {{{1
    my ($file       , # in
        $excluded   , # in   hash of excluded directories
       ) = @_;
    my($filename, $filepath, $suffix) = fileparse($file);
    foreach my $path (sort keys %{$excluded}) {
        return 1 if ($filepath =~ m{^$path/}i);
    }
} # 1}}}
sub classify_file {                          # {{{1
    my ($full_file   , # in
        $rh_Err      , # in   hash of error codes
        $raa_errors  , # out
        $rh_ignored  , # out
       ) = @_;

    print "-> classify_file($full_file)\n" if $opt_v > 2;
    my $language = "(unknown)";

    my $look_at_first_line = 0;
    my $file = basename $full_file; 
    if ($opt_autoconf and $file =~ /\.in$/) {
       $file =~ s/\.in$//;
    }
    return $language if $Not_Code_Filename{$file}; # (unknown)
    return $language if $file =~ m{~$}; # a temp edit file (unknown)
    if (defined $Language_by_File{$file}) {
        return $Language_by_File{$file};
    }

    if ($file =~ /\.(\w+)$/) { # has an extension
      print "$full_file extension=[$1]\n" if $opt_v > 2;
      my $extension = $1;
         # Windows file names are case insensitive so map 
         # all extensions to lowercase there.
         $extension = lc $extension if $ON_WINDOWS;  
      my @extension_list = ( $extension );
      if ($file =~ /\.(\w+\.\w+)$/) { # has a double extension
          my $extension = $1;
          $extension = lc $extension if $ON_WINDOWS;  
          unshift @extension_list, $extension;  # examine double ext first
      }
      foreach my $extension (@extension_list) {
        if ($Not_Code_Extension{$extension} and 
           !$Forced_Extension{$extension}) {
           # If .1 (for example) is an extension that would ordinarily be
           # ignored but the user has insisted this be counted with the
           # --force-lang option, then go ahead and count it.
            $rh_ignored->{$full_file} = 
                'listed in $Not_Code_Extension{' . $extension . '}';
            return $language;
        }
        if (defined $Language_by_Extension{$extension}) {
            if ($Language_by_Extension{$extension} eq
                'MATLAB/Objective C/MUMPS') {
                my $lang_M_or_O = "";
                matlab_or_objective_C($full_file , 
                                      $rh_Err    ,
                                      $raa_errors,
                                     \$lang_M_or_O);
                if ($lang_M_or_O) {
                    return $lang_M_or_O;
                } else { # an error happened in matlab_or_objective_C()
                    $rh_ignored->{$full_file} = 
                        'failure in matlab_or_objective_C()';
                    return $language; # (unknown)
                }
            } elsif ($Language_by_Extension{$extension} eq 'PHP/Pascal') {
                if (really_is_php($full_file)) {
                    return 'PHP';
                } elsif (really_is_incpascal($full_file)) {
                    return 'Pascal';
                } else {
                    return $language; # (unknown)
                }
            } elsif ($Language_by_Extension{$extension} eq 'Smarty') {
                # Smarty extension .tpl is generic; make sure the
                # file at least roughly resembles PHP
                if (really_is_php($full_file)) {
                    return 'Smarty';
                } else {
                    return $language; # (unknown)
                }
            } else {
                return $Language_by_Extension{$extension};
            }
        } else { # has an unmapped file extension
            $look_at_first_line = 1;
        }
      }
    } elsif (defined $Language_by_File{lc $file}) {
        return $Language_by_File{lc $file};
    } elsif ($opt_lang_no_ext and 
             defined $Filters_by_Language{$opt_lang_no_ext}) {
        return $opt_lang_no_ext;
    } else {  # no file extension
        $look_at_first_line = 1;
    }

    if ($look_at_first_line) {
        # maybe it is a shell/Perl/Python/Ruby/etc script that
        # starts with pound bang:
        #   #!/usr/bin/perl
        #   #!/usr/bin/env perl
        my $script_language = peek_at_first_line($full_file , 
                                                 $rh_Err    , 
                                                 $raa_errors);
        if (!$script_language) {
            $rh_ignored->{$full_file} = "language unknown (#2)";
            # returns (unknown)
        }
        if (defined $Language_by_Script{$script_language}) {
            if (defined $Filters_by_Language{
                            $Language_by_Script{$script_language}}) {
                $language = $Language_by_Script{$script_language};
            } else {
                $rh_ignored->{$full_file} = 
                    "undefined:  Filters_by_Language{" . 
                    $Language_by_Script{$script_language} .
                    "} for scripting language $script_language";
                # returns (unknown)
            }
        } else {
            $rh_ignored->{$full_file} = "language unknown (#3)";
            # returns (unknown)
        }
    }
    print "<- classify_file($full_file)\n" if $opt_v > 2;
    return $language;
} # 1}}}
sub peek_at_first_line {                     # {{{1
    my ($file        , # in
        $rh_Err      , # in   hash of error codes
        $raa_errors  , # out
       ) = @_;

    print "-> peek_at_first_line($file)\n" if $opt_v > 2;

    my $script_language = "";
    if (!-r $file) {
        push @{$raa_errors}, [$rh_Err->{'Unable to read'} , $file];
        return $script_language;
    }
    my $IN = new IO::File $file, "r";
    if (!defined $IN) {
        push @{$raa_errors}, [$rh_Err->{'Unable to read'} , $file];
        print "<- peek_at_first_line($file)\n" if $opt_v > 2;
        return $script_language;
    }
    chomp(my $first_line = <$IN>);
    if (defined $first_line) {
#print "peek_at_first_line of [$file] first_line=[$first_line]\n";
        if ($first_line =~ /^#\!\s*(\S.*?)$/) {
#print "peek_at_first_line 1=[$1]\n";
            my @pound_bang = split(' ', $1);
#print "peek_at_first_line basename 0=[", basename($pound_bang[0]), "]\n";
            if (basename($pound_bang[0]) eq "env" and 
                scalar @pound_bang > 1) {
                $script_language = $pound_bang[1];
#print "peek_at_first_line pound_bang A $pound_bang[1]\n";
            } else {
                $script_language = basename $pound_bang[0];
#print "peek_at_first_line pound_bang B $script_language\n";
            }
        }
    }
    $IN->close;
    print "<- peek_at_first_line($file)\n" if $opt_v > 2;
    return $script_language;
} # 1}}}
sub different_files {                        # {{{1
    # See which of the given files are unique by computing each file's MD5
    # sum.  Return the subset of files which are unique.
    my ($ra_files    , # in
        $rh_Err      , # in
        $raa_errors  , # out
        $rh_ignored  , # out
       ) = @_;

    print "-> different_files(@{$ra_files})\n" if $opt_v > 2;
    my %file_hash = ();  # file_hash{md5 hash} = [ file1, file2, ... ]
    foreach my $F (@{$ra_files}) {
        next if is_dir($F);  # needed for Windows
        my $IN = new IO::File $F, "r";
        if (!defined $IN) {
            push @{$raa_errors}, [$rh_Err->{'Unable to read'} , $F];
            $rh_ignored->{$F} = 'cannot read';
        } else {
            if ($HAVE_Digest_MD5) {
                binmode $IN;
                my $MD5 = Digest::MD5->new->addfile($IN)->hexdigest;
                push @{$file_hash{$MD5}}, $F;
            } else {
                # all files treated unique
                push @{$file_hash{$F}}, $F;
            }
            $IN->close;
        }
    }

    # Loop over file sets having identical MD5 sums.  Within
    # each set, pick the file that most resembles known source 
    # code.
    my @unique = ();
    for my $md5 (sort keys %file_hash) {
        my $i_best = 0;
        for (my $i = 1; $i < scalar(@{$file_hash{$md5}}); $i++) {
            my $F = $file_hash{$md5}[$i];
            my (@nul_a, %nul_h);
            my $language = classify_file($F, $rh_Err, 
                                        # don't save these errors; pointless
                                        \@nul_a, \%nul_h);
            $i_best = $i if $language ne "(unknown)";
        }
        push @unique, $file_hash{$md5}[$i_best];
    }
    print "<- different_files(@unique)\n" if $opt_v > 2;
    return @unique;
} # 1}}}
sub call_counter {                           # {{{1
    my ($file     , # in
        $language , # in
        $ra_Errors, # out
       ) = @_;

    # Logic:  pass the file through the following filters:
    #         1. remove blank lines
    #         2. remove comments using each filter defined for this language
    #            (example:  SQL has two, remove_starts_with(--) and 
    #             remove_c_comments() )
    #         3. compute comment lines as 
    #               total lines - blank lines - lines left over after all
    #                   comment filters have been applied

    print "-> call_counter($file, $language)\n" if $opt_v > 2;
#print "call_counter:  ", Dumper(@routines), "\n";

    my @lines = ();
    my $ascii = "";
    if (-B $file and $opt_unicode) {
        # was binary so must be unicode

        $/ = undef;
        my $IN = new IO::File $file, "r";
        my $bin_text = <$IN>;
        $IN->close;
        $/ = "\n";

        $ascii = unicode_to_ascii( $bin_text );
        @lines = split("\n", $ascii );
        foreach (@lines) { $_ = "$_\n"; }

    } else {
        # regular text file
        @lines = read_file($file);
        $ascii = join('', @lines);
    }

    my @original_lines = @lines;
    my $total_lines    = scalar @lines;

    print_lines($file, "Original file:", \@lines) if $opt_print_filter_stages;
    @lines = rm_blanks(\@lines, $language, \%EOL_Continuation_re); # remove blank lines
    my $blank_lines = $total_lines - scalar @lines;
    print_lines($file, "Blank lines removed:", \@lines) 
        if $opt_print_filter_stages;

    @lines = rm_comments(\@lines, $language, $file,
                               \%EOL_Continuation_re);

    my $comment_lines = $total_lines - $blank_lines - scalar  @lines;
    if ($opt_strip_comments) {
        my $stripped_file = "";
        if ($opt_original_dir) {
            $stripped_file =          $file . ".$opt_strip_comments";
        } else {
            $stripped_file = basename $file . ".$opt_strip_comments";
        }
        write_file($stripped_file, @lines);
    }
    if ($opt_html and !$opt_diff) {
        chomp(@original_lines);  # includes blank lines, comments
        chomp(@lines);           # no blank lines, no comments

        my (@diff_L, @diff_R, %count);

        # remove blank lines to get better quality diffs; count
        # blank lines separately
        my @original_lines_minus_white = ();
        # however must keep track of how many blank lines were removed and
        # where they were removed so that the HTML display can include it
        my %blank_line  = ();
        my $insert_line = 0;
        foreach (@original_lines) {
            if (/^\s*$/) {
               ++$count{blank}{same};
               ++$blank_line{ $insert_line };
            } else {
                ++$insert_line;
                push @original_lines_minus_white, $_;
            }
        }

        array_diff( $file                       ,   # in
                   \@original_lines_minus_white ,   # in
                   \@lines                      ,   # in
                   "comment"                    ,   # in
                   \@diff_L, \@diff_R,          ,   # out
                    $ra_Errors);                    # in/out
        write_comments_to_html($file, \@diff_L, \@diff_R, \%blank_line);
#print Dumper("count", \%count);
    }

    print "<- call_counter($total_lines, $blank_lines, $comment_lines)\n" 
        if $opt_v > 2;
    return ($total_lines, $blank_lines, $comment_lines);
} # 1}}}
sub windows_glob {                           # {{{1
    # Windows doesn't expand wildcards.  Use code from Sean M. Burke's 
    # Win32::Autoglob module to do this.
    return map {;
        ( defined($_) and m/[\*\?]/ ) ? sort(glob($_)) : $_
          } @_; 
} # 1}}}
sub write_file {                             # {{{1
    my ($file  , # in
        @lines , # in
       ) = @_;

#print "write_file 1 [$file]\n";
    # Do ~ expansion (by Tim LaBerge, fixes bug 2787984)
    my $preglob_filename = $file;
#print "write_file 2 [$preglob_filename]\n";
    if ($ON_WINDOWS) {
        $file = (windows_glob($file))[0];
    } else {
        $file = glob($file);  # sometimes returns null string
    }
#print "write_file 3 [$file]\n";
    $file = $preglob_filename unless $file;
#print "write_file 4 [$file]\n";

    print "-> write_file($file)\n" if $opt_v > 2;

    # Create the destination directory if it doesn't already exist.
    my $abs_file_path = File::Spec->rel2abs( $file );
    my ($volume, $directories, $filename) = File::Spec->splitpath( $abs_file_path );
    mkpath($volume . $directories, 1, 0777);
    
    my $OUT = new IO::File $file, "w";
    if (defined $OUT) {
        chomp(@lines);
        print $OUT join("\n", @lines), "\n";
        $OUT->close;
    } else {
        warn "Unable to write to $file\n";
    }
    print "Wrote $file";
    print ", $CLOC_XSL" if $opt_xsl and $opt_xsl eq $CLOC_XSL;
    print "\n";
    
    print "<- write_file\n" if $opt_v > 2;
} # 1}}}
sub read_file  {                             # {{{1
    my ($file, ) = @_;

    print "-> read_file($file)\n" if $opt_v > 2;
    my @lines = ();
    my $IN = new IO::File $file, "r";
    if (defined $IN) {
        @lines = <$IN>;
        $IN->close;
        # Some files don't end with a new line.  Force this:
        $lines[$#lines] .= "\n" unless $lines[$#lines] =~ m/\n$/;
    } else {
        warn "Unable to read $file\n";
    }
    print "<- read_file\n" if $opt_v > 2;
    return @lines;
} # 1}}}
sub rm_blanks {                              # {{{1
    my ($ra_in    ,
        $language ,
        $rh_EOL_continuation_re) = @_;
    print "-> rm_blanks(language=$language)\n" if $opt_v > 2;
#print "rm_blanks: language = [$language]\n";
    my @out = ();
    if ($language eq "COBOL") {
        @out = remove_cobol_blanks($ra_in);
    } else {
        # removes blank lines
        if (defined $rh_EOL_continuation_re->{$language}) {
            @out = remove_matches_2re($ra_in, '^\s*$', 
                                      $rh_EOL_continuation_re->{$language}); 
        } else {
            @out = remove_matches($ra_in, '^\s*$');
        }
    }
    print "<- rm_blanks(language=$language)\n" if $opt_v > 2;
    return @out;
} # 1}}}
sub rm_comments {                            # {{{1
    my ($ra_lines , # in, must be free of blank lines
        $language , # in
        $file     , # in (some language counters, eg Haskell, need 
                    #     access to the original file)
        $rh_EOL_continuation_re , # in
       ) = @_;
    print "-> rm_comments(file=$file)\n" if $opt_v > 2;
    my @routines       = @{$Filters_by_Language{$language}};
    my @lines          = @{$ra_lines};
    my @original_lines = @{$ra_lines};

    foreach my $call_string (@routines) {
        my $subroutine = $call_string->[0];
        if (! defined &{$subroutine}) {
            warn "rm_comments undefined subroutine $subroutine for $file\n";
            next;
        }
        print "rm_comments file=$file sub=$subroutine\n" if $opt_v > 1;
        my @args  = @{$call_string};
        shift @args; # drop the subroutine name
        if (@args and $args[0] eq '>filename<') {
            shift   @args;
            unshift @args, $file;
        }

        no strict 'refs';
        @lines = &{$subroutine}(\@lines, @args);   # apply filter...

        print_lines($file, "After $subroutine(@args)", \@lines) 
            if $opt_print_filter_stages;
        # then remove blank lines which are created by comment removal
        if (defined $rh_EOL_continuation_re->{$language}) {
            @lines = remove_matches_2re(\@lines, '^\s*$',
                                        $rh_EOL_continuation_re);
        } else {
            @lines = remove_matches(\@lines, '^\s*$');
        }
        
        print_lines($file, "post $subroutine(@args) blank cleanup:", \@lines) 
            if $opt_print_filter_stages;
    }
    # Exception for scripting languages:  treat the first #! line as code.
    # Will need to add it back in if it was removed earlier.
    if ($Script_Language{$language} and 
        $original_lines[0] =~ /^#!/ and
        (scalar(@lines) == 0 or 
         $lines[0] ne $original_lines[0])) {
        unshift @lines, $original_lines[0];  # add the first line back
    }
    print "<- rm_comments\n" if $opt_v > 2;
    return @lines;
} # 1}}}
sub remove_f77_comments {                    # {{{1
    my ($ra_lines, ) = @_;
    print "-> remove_f77_comments\n" if $opt_v > 2;

    my @save_lines = ();
    foreach (@{$ra_lines}) {
        next if m{^[*cC]};
        next if m{^\s*!};
        push @save_lines, $_;
    }

    print "<- remove_f77_comments\n" if $opt_v > 2;
    return @save_lines;
} # 1}}}
sub remove_f90_comments {                    # {{{1
    # derived from SLOCCount
    my ($ra_lines, ) = @_;
    print "-> remove_f90_comments\n" if $opt_v > 2;

    my @save_lines = ();
    foreach (@{$ra_lines}) {
        # a comment is              m/^\s*!/
        # an empty line is          m/^\s*$/
        # a HPF statement is        m/^\s*!hpf\$/i
        # an Open MP statement is   m/^\s*!omp\$/i
        if (! m/^(\s*!|\s*$)/ || m/^\s*!(hpf|omp)\$/i) {
            push @save_lines, $_;
        }
    }

    print "<- remove_f90_comments\n" if $opt_v > 2;
    return @save_lines;
} # 1}}}
sub remove_matches {                         # {{{1
    my ($ra_lines, # in
        $pattern , # in   Perl regular expression (case insensitive)
       ) = @_;
    print "-> remove_matches(pattern=$pattern)\n" if $opt_v > 2;

    my @save_lines = ();
    foreach (@{$ra_lines}) {
#chomp; print "remove_matches [$pattern] [$_]\n";
        next if m{$pattern}i;
        push @save_lines, $_;
    }

    print "<- remove_matches\n" if $opt_v > 2;
#print "remove_matches returning\n   ", join("\n   ", @save_lines), "\n";
    return @save_lines;
} # 1}}}
sub remove_matches_2re {                     # {{{1
    my ($ra_lines, # in
        $pattern1, # in Perl regex 1 (case insensitive) to match
        $pattern2, # in Perl regex 2 (case insensitive) to not match prev line
       ) = @_;
    print "-> remove_matches_2re(pattern=$pattern1,$pattern2)\n" if $opt_v > 2;

    my @save_lines = ();
    for (my $i = 0; $i < scalar @{$ra_lines}; $i++) {
#print "remove_matches_2re [$pattern1] [$pattern2] [$ra_lines->[$i]]\n";
        if ($i) {
#print "remove_matches_2re prev=[$ra_lines->[$i-1]] this=[$ra_lines->[$i]]\n";
            next if ($ra_lines->[$i]   =~ m{$pattern1}i) and 
                    ($ra_lines->[$i-1] !~ m{$pattern2}i);
        } else {
            # on first line
            next if $ra_lines->[$i]   =~  m{$pattern1}i;
        }
        push @save_lines, $ra_lines->[$i];
    }

    print "<- remove_matches_2re\n" if $opt_v > 2;
#print "remove_matches_2re returning\n   ", join("\n   ", @save_lines), "\n";
    return @save_lines;
} # 1}}}
sub remove_inline {                          # {{{1
    my ($ra_lines, # in
        $pattern , # in   Perl regular expression (case insensitive)
       ) = @_;
    print "-> remove_inline(pattern=$pattern)\n" if $opt_v > 2;

    my @save_lines = ();
    unless ($opt_inline) {
        return @{$ra_lines};
    }
    my $nLines_affected = 0;
    foreach (@{$ra_lines}) {
#chomp; print "remove_inline [$pattern] [$_]\n";
        if (m{$pattern}i) {
            ++$nLines_affected;
            s{$pattern}{}i;
        }
        push @save_lines, $_;
    }

    print "<- remove_inline\n" if $opt_v > 2;
#print "remove_inline returning\n   ", join("\n   ", @save_lines), "\n";
    return @save_lines;
} # 1}}}
sub remove_above {                           # {{{1
    my ($ra_lines, $marker, ) = @_;
    print "-> remove_above(marker=$marker)\n" if $opt_v > 2;

    # Make two passes through the code:
    # 1. check if the marker exists
    # 2. remove anything above the marker if it exists,
    #    do nothing if the marker does not exist

    # Pass 1
    my $found_marker = 0;
    for (my $line_number  = 1;
            $line_number <= scalar @{$ra_lines};
            $line_number++) {
        if ($ra_lines->[$line_number-1] =~ m{$marker}) {
            $found_marker = $line_number;
            last;
        }
    }

    # Pass 2 only if needed
    my @save_lines = ();
    if ($found_marker) {
        my $n = 1;
        foreach (@{$ra_lines}) {
            push @save_lines, $_
                if $n >= $found_marker;
            ++$n;
        }
    } else { # marker wasn't found; save all lines
        foreach (@{$ra_lines}) {
            push @save_lines, $_;
        }
    }

    print "<- remove_above\n" if $opt_v > 2;
    return @save_lines;
} # 1}}}
sub remove_below {                           # {{{1
    my ($ra_lines, $marker, ) = @_;
    print "-> remove_below(marker=$marker)\n" if $opt_v > 2;

    my @save_lines = ();
    foreach (@{$ra_lines}) {
        last if m{$marker};
        push @save_lines, $_;
    }

    print "<- remove_below\n" if $opt_v > 2;
    return @save_lines;
} # 1}}}
sub remove_below_above {                     # {{{1
    my ($ra_lines, $marker_below, $marker_above, ) = @_;
    # delete lines delimited by start and end line markers such
    # as Perl POD documentation
    print "-> remove_below_above(markerB=$marker_below, A=$marker_above)\n" 
        if $opt_v > 2;

    my @save_lines = ();
    my $between    = 0;
    foreach (@{$ra_lines}) {
        if (!$between and m{$marker_below}) {
            $between    = 1;
            next;
        }
        if ($between and m{$marker_above}) {
            $between    = 0;
            next;
        }
        next if $between;
        push @save_lines, $_;
    }

    print "<- remove_below_above\n" if $opt_v > 2;
    return @save_lines;
} # 1}}}
sub remove_between {                         # {{{1
    my ($ra_lines, $marker, ) = @_;
    # $marker must contain one of the balanced pairs understood
    # by Regexp::Common::balanced, namely
    # '{}'  '()'  '[]'  or  '<>'

    print "-> remove_between(marker=$marker)\n" if $opt_v > 2;
    my %acceptable = ('{}'=>1,  '()'=>1,  '[]'=>1,  '<>'=>1, );
    die "remove_between:  invalid delimiter '$marker'\n",
        "the delimiter must be one of these four pairs:\n",
        "{}  ()  []  <>\n" unless
        $acceptable{$marker};

    Install_Regexp_Common() unless $HAVE_Rexexp_Common;

    my $all_lines = join("", @{$ra_lines});

    no strict 'vars';
    # otherwise get:
    #  Global symbol "%RE" requires explicit package name at cloc line xx.
    if ($all_lines =~ m/$RE{balanced}{-parens => $marker}/) {
        no warnings; 
        $all_lines =~ s/$1//g;
    }

    print "<- remove_between\n" if $opt_v > 2;
    return split("\n", $all_lines);
} # 1}}}
sub remove_cobol_blanks {                    # {{{1
    # subroutines derived from SLOCCount
    my ($ra_lines, ) = @_;

    my $free_format = 0;  # Support "free format" source code.
    my @save_lines  = ();
  
    foreach (@{$ra_lines}) {
        next if m/^\s*$/;
        my $line = expand($_);  # convert tabs to equivalent spaces
        $free_format = 1 if $line =~ m/^......\$.*SET.*SOURCEFORMAT.*FREE/i;
        if ($free_format) {
            push @save_lines, $_;
        } else {
            # Greg Toth:
            #  (1) Treat lines with any alphanum in cols 1-6 and 
            #      blanks in cols 7 through 71 as blank line, and
            #  (2) Treat lines with any alphanum in cols 1-6 and 
            #      slash (/) in col 7 as blank line (this is a 
            #      page eject directive). 
            push @save_lines, $_ unless m/^\d{6}\s*$/             or 
                                        ($line =~ m/^.{6}\s{66}/) or 
                                        ($line =~ m/^......\//);
        }
    }
    return @save_lines;
} # 1}}}
sub remove_cobol_comments {                  # {{{1
    # subroutines derived from SLOCCount
    my ($ra_lines, ) = @_;

    my $free_format = 0;  # Support "free format" source code.
    my @save_lines  = ();
  
    foreach (@{$ra_lines}) {
        if (m/^......\$.*SET.*SOURCEFORMAT.*FREE/i) {$free_format = 1;}
        if ($free_format) {
            push @save_lines, $_ unless m{^\s*\*};
        } else {
            push @save_lines, $_ unless m{^......\*} or m{^\*};
        }
    }
    return @save_lines;
} # 1}}}
sub remove_jcl_comments {                    # {{{1
    my ($ra_lines, ) = @_;

    print "-> remove_jcl_comments\n" if $opt_v > 2;

    my @save_lines = ();
    my $in_comment = 0;
    foreach (@{$ra_lines}) {
        next if /^\s*$/;
        next if m{^\s*//\*};
        last if m{^\s*//\s*$};
        push @save_lines, $_;
    }

    print "<- remove_jcl_comments\n" if $opt_v > 2;
    return @save_lines;
} # 1}}}
sub remove_jsp_comments {                    # {{{1
    #  JSP comment is   <%--  body of comment   --%>
    my ($ra_lines, ) = @_;

    print "-> remove_jsp_comments\n" if $opt_v > 2;

    my @save_lines = ();
    my $in_comment = 0;
    foreach (@{$ra_lines}) {

        next if /^\s*$/;
        s/<\%\-\-.*?\-\-\%>//g;  # strip one-line comments
        next if /^\s*$/;
        if ($in_comment) {
            if (/\-\-\%>/) {
                s/^.*?\-\-\%>//;
                $in_comment = 0;
            }
        }
        next if /^\s*$/;
        $in_comment = 1 if /^(.*?)<\%\-\-/;
        next if defined $1 and $1 =~ /^\s*$/;
        next if ($in_comment);
        push @save_lines, $_;
    }

    print "<- remove_jsp_comments\n" if $opt_v > 2;
    return @save_lines;
} # 1}}}
sub remove_html_comments {                   # {{{1
    #  HTML comment is   <!--  body of comment   -->
    #  Need to use my own routine until the HTML comment regex in
    #  the Regexp::Common module can handle  <!--  --  -->
    my ($ra_lines, ) = @_;

    print "-> remove_html_comments\n" if $opt_v > 2;

    my @save_lines = ();
    my $in_comment = 0;
    foreach (@{$ra_lines}) {

        next if /^\s*$/;
        s/<!\-\-.*?\-\->//g;  # strip one-line comments
        next if /^\s*$/;
        if ($in_comment) {
            if (/\-\->/) {
                s/^.*?\-\->//;
                $in_comment = 0;
            }
        }
        next if /^\s*$/;
        $in_comment = 1 if /^(.*?)<!\-\-/;
        next if defined $1 and $1 =~ /^\s*$/;
        next if ($in_comment);
        push @save_lines, $_;
    }

    print "<- remove_html_comments\n" if $opt_v > 2;
    return @save_lines;
} # 1}}}
sub add_newlines {                           # {{{1
    my ($ra_lines, ) = @_;
    print "-> add_newlines \n" if $opt_v > 2;

    my @save_lines = ();
    foreach (@{$ra_lines}) {

        push @save_lines, "$_\n";
    }

    print "<- add_newlines \n" if $opt_v > 2;
    return @save_lines;
} # 1}}}
sub docstring_to_C {                         # {{{1
    my ($ra_lines, ) = @_;
    # Converts Python docstrings to C comments.

    print "-> docstring_to_C()\n" if $opt_v > 2;

    my $in_docstring = 0;
    foreach (@{$ra_lines}) {
        while (/"""/) {
            if (!$in_docstring) {
                s{"""}{/*};
                $in_docstring = 1;
            } else {
                s{"""}{*/};
                $in_docstring = 0;
            }
        }
    }

    print "<- docstring_to_C\n" if $opt_v > 2;
    return @{$ra_lines};
} # 1}}}
sub smarty_to_C {                            # {{{1
    my ($ra_lines, ) = @_;
    # Converts Smarty comments to C comments.

    print "-> smarty_to_C()\n" if $opt_v > 2;

    foreach (@{$ra_lines}) {
        s[{\*][/*]g;
        s[\*}][*/]g;
    }

    print "<- smarty_to_C\n" if $opt_v > 2;
    return @{$ra_lines};
} # 1}}}
sub determine_lit_type {                     # {{{1
  my ($file) = @_;

  open (FILE, $file);
  while (<FILE>) {
    if (m/^\\begin{code}/) { close FILE; return 2; }
    if (m/^>\s/) { close FILE; return 1; }
  }

  return 0;
} # 1}}}
sub remove_haskell_comments {                # {{{1
    # Bulk of code taken from SLOCCount's haskell_count script.
    # Strips out {- .. -} and -- comments and counts the rest.
    # Pragmas, {-#...}, are counted as SLOC.
    # BUG: Doesn't handle strings with embedded block comment markers gracefully.
    #      In practice, that shouldn't be a problem.
    my ($ra_lines, $file, ) = @_;

    print "-> remove_haskell_comments\n" if $opt_v > 2;

    my @save_lines = ();
    my $in_comment = 0;
    my $incomment  = 0;
    my ($literate, $inlitblock) = (0,0);
  
    $literate = 1 if $file =~ /\.lhs$/;
    if($literate) { $literate = determine_lit_type($file) }

    foreach (@{$ra_lines}) {
        if ($literate == 1) {
            if (!s/^>//) { s/.*//; }
        } elsif ($literate == 2) {
            if ($inlitblock) {
                if (m/^\\end{code}/) { s/.*//; $inlitblock = 0; }
            } elsif (!$inlitblock) {
                if (m/^\\begin{code}/) { s/.*//; $inlitblock = 1; }
                else { s/.*//; }
            }
        }

        if ($incomment) {
            if (m/\-\}/) { s/^.*?\-\}//;  $incomment = 0;}
            else { s/.*//; }
        }
        if (!$incomment) {
            s/--.*//;
            s!{-[^#].*?-}!!g;
            if (m/{-/ && (!m/{-#/)) {
              s/{-.*//;
              $incomment = 1;
            }
        }
        if (m/\S/) { push @save_lines, $_; }
    }
#   if ($incomment) {print "ERROR: ended in comment in $ARGV\n";}

    print "<- remove_haskell_comments\n" if $opt_v > 2;
    return @save_lines;
} # 1}}}
sub print_lines {                            # {{{1
    my ($file     , # in
        $title    , # in
        $ra_lines , # in
       ) = @_;
    printf "->%-30s %s\n", $file, $title;
    for (my $i = 0; $i < scalar @{$ra_lines}; $i++) {
        printf "%5d | %s", $i+1, $ra_lines->[$i];
        print "\n" unless $ra_lines->[$i] =~ m{\n$}
    }
} # 1}}}
sub set_constants {                          # {{{1
    my ($rh_Language_by_Extension , # out
        $rh_Language_by_Script    , # out
        $rh_Language_by_File      , # out
        $rhaa_Filters_by_Language , # out
        $rh_Not_Code_Extension    , # out
        $rh_Not_Code_Filename     , # out
        $rh_Scale_Factor          , # out
        $rh_Known_Binary_Archives , # out
        $rh_EOL_continuation_re   , # out
       ) = @_;
# 1}}}
%{$rh_Language_by_Extension} = (                 # {{{1
            'abap'        => 'ABAP'                  ,
            'ac'          => 'm4'                    ,
            'ada'         => 'Ada'                   ,
            'adb'         => 'Ada'                   ,
            'ads'         => 'Ada'                   ,
            'adso'        => 'ADSO/IDSM'             ,
            'am'          => 'make'                  ,
            'ample'       => 'AMPLE'                 ,
            'as'          => 'ActionScript'          ,
            'dofile'      => 'AMPLE'                 ,
            'startup'     => 'AMPLE'                 ,
            'asa'         => 'ASP'                   ,
            'asax'        => 'ASP.Net'               ,
            'ascx'        => 'ASP.Net'               ,
            'asm'         => 'Assembly'              ,
            'asmx'        => 'ASP.Net'               ,
            'asp'         => 'ASP'                   ,
            'aspx'        => 'ASP.Net'               ,
            'master'      => 'ASP.Net'               ,
            'sitemap'     => 'ASP.Net'               ,
            'awk'         => 'awk'                   ,
            'bash'        => 'Bourne Again Shell'    ,
            'bas'         => 'Visual Basic'          ,
            'bat'         => 'DOS Batch'             ,
            'BAT'         => 'DOS Batch'             ,
            'cbl'         => 'COBOL'                 ,
            'CBL'         => 'COBOL'                 ,
            'c'           => 'C'                     ,
            'C'           => 'C++'                   ,
            'cc'          => 'C++'                   ,
            'ccs'         => 'CCS'                   ,
            'cfm'         => 'ColdFusion'            ,
            'cl'          => 'Lisp'                  ,
            'cls'         => 'Visual Basic'          ,
            'CMakeLists.txt' => 'CMake'              ,
            'cob'         => 'COBOL'                 ,
            'COB'         => 'COBOL'                 ,
            'config'      => 'ASP.Net'               ,
            'cpp'         => 'C++'                   ,
            'cs'          => 'C#'                    ,
            'csh'         => 'C Shell'               ,
            'css'         => "CSS"                   ,
            'cxx'         => 'C++'                   ,
            'd'           => 'D'                     ,
            'da'          => 'DAL'                   ,
            'dart'        => 'Dart'                  ,
            'def'         => 'Teamcenter def'        ,
            'dmap'        => 'NASTRAN DMAP'          ,
            'dpr'         => 'Pascal'                ,
            'dtd'         => 'DTD'                   ,
            'ec'          => 'C'                     ,
            'el'          => 'Lisp'                  ,
            'erl'         => 'Erlang'                ,
            'exp'         => 'Expect'                ,
            'f77'         => 'Fortran 77'            ,
            'F77'         => 'Fortran 77'            ,
            'f90'         => 'Fortran 90'            ,
            'F90'         => 'Fortran 90'            ,
            'f95'         => 'Fortran 95'            ,
            'F95'         => 'Fortran 95'            ,
            'f'           => 'Fortran 77'            ,
            'F'           => 'Fortran 77'            ,
            'fmt'         => 'Oracle Forms'          ,
            'focexec'     => 'Focus'                 ,
            'frm'         => 'Visual Basic'          ,
            'gnumakefile' => 'make'                  ,
            'Gnumakefile' => 'make'                  ,
            'go'          => 'Go'                    ,
            'groovy'      => 'Groovy'                ,
            'h'           => 'C/C++ Header'          ,
            'H'           => 'C/C++ Header'          ,
            'hh'          => 'C/C++ Header'          ,
            'hpp'         => 'C/C++ Header'          ,
            'hrl'         => 'Erlang'                ,
            'hs'          => 'Haskell'               , 
            'htm'         => 'HTML'                  ,
            'html'        => 'HTML'                  ,
            'i3'          => 'Modula3'               ,
            'idl'         => 'IDL'                   ,
            'pro'         => 'IDL'                   ,
            'ig'          => 'Modula3'               ,
            'il'          => 'SKILL'                 ,
            'ils'         => 'SKILL++'               ,
            'inc'         => 'PHP/Pascal'            , # might be PHP or Pascal
            'itk'         => 'Tcl/Tk'                ,
            'java'        => 'Java'                  ,
            'jcl'         => 'JCL'                   , # IBM Job Control Lang.
            'jl'          => 'Lisp'                  ,
            'js'          => 'Javascript'            ,
            'jsp'         => 'JSP'                   , # Java server pages
            'ksc'         => 'Kermit'                ,
            'ksh'         => 'Korn Shell'            ,
            'lhs'         => 'Haskell'               ,
            'l'           => 'lex'                   ,
            'lsp'         => 'Lisp'                  ,
            'lisp'        => 'Lisp'                  ,
            'lua'         => 'Lua'                   ,
            'm3'          => 'Modula3'               ,
            'm4'          => 'm4'                    ,
            'makefile'    => 'make'                  ,
            'Makefile'    => 'make'                  ,
            'met'         => 'Teamcenter met'        ,
            'mg'          => 'Modula3'               , 
#           'mli'         => 'ML'                    , # ML not implemented
#           'ml'          => 'ML'                    , 
            'ml'          => 'Ocaml'                 , 
            'm'           => 'MATLAB/Objective C/MUMPS' ,
            'mm'          => 'Objective C++'         ,
            'wdproj'      => 'MSBuild scripts'       ,
            'csproj'      => 'MSBuild scripts'       ,
            'mps'         => 'MUMPS'                 ,
            'mth'         => 'Teamcenter mth'        ,
            'oscript'     => 'LiveLink OScript'      ,
            'pad'         => 'Ada'                   , # Oracle Ada preprocessor
            'pas'         => 'Pascal'                ,
            'pcc'         => 'C++'                   , # Oracle C++ preprocessor
            'perl'        => 'Perl'                  ,
            'pfo'         => 'Fortran 77'            ,
            'pgc'         => 'C'                     , # Postgres embedded C/C++
            'php3'        => 'PHP'                   ,
            'php4'        => 'PHP'                   ,
            'php5'        => 'PHP'                   ,
            'php'         => 'PHP'                   ,
            'plh'         => 'Perl'                  ,
            'pl'          => 'Perl'                  ,
            'PL'          => 'Perl'                  ,
            'plx'         => 'Perl'                  ,
            'pm'          => 'Perl'                  ,
            'p'           => 'Pascal'                ,
            'pp'          => 'Pascal'                ,
            'psql'        => 'SQL'                   ,
            'py'          => 'Python'                ,
            'pyx'         => 'Cython'                ,
            'rb'          => 'Ruby'                  ,
         #  'resx'        => 'ASP.Net'               ,
            'rex'         => 'Oracle Reports'        ,
            'rexx'        => 'Rexx'                  ,
            'rhtml'       => 'Ruby HTML'             ,
            's'           => 'Assembly'              ,
            'S'           => 'Assembly'              ,
            'scala'       => 'Scala'                 ,
            'sbl'         => 'Softbridge Basic'      ,
            'SBL'         => 'Softbridge Basic'      ,
            'sc'          => 'Lisp'                  ,
            'scm'         => 'Lisp'                  ,
            'sed'         => 'sed'                   ,
            'ses'         => 'Patran Command Language'   ,
            'pcl'         => 'Patran Command Language'   ,
            'sh'          => 'Bourne Shell'          ,
            'smarty'      => 'Smarty'                ,
            'sql'         => 'SQL'                   ,
            'SQL'         => 'SQL'                   ,
            'sproc.sql'   => 'SQL Stored Procedure'  ,
            'spoc.sql'    => 'SQL Stored Procedure'  ,
            'spc.sql'     => 'SQL Stored Procedure'  ,
            'udf.sql'     => 'SQL Stored Procedure'  ,
            'data.sql'    => 'SQL Data'              ,
            'tcl'         => 'Tcl/Tk'                ,
            'tcsh'        => 'C Shell'               ,
            'tk'          => 'Tcl/Tk'                ,
            'tpl'         => 'Smarty'                ,
            'vhd'         => 'VHDL'                  ,
            'VHD'         => 'VHDL'                  ,
            'vhdl'        => 'VHDL'                  ,
            'VHDL'        => 'VHDL'                  ,
            'vba'         => 'Visual Basic'          ,
            'VBA'         => 'Visual Basic'          ,
         #  'vbp'         => 'Visual Basic'          , # .vbp - autogenerated
            'vb'          => 'Visual Basic'          ,
            'VB'          => 'Visual Basic'          ,
         #  'vbw'         => 'Visual Basic'          , # .vbw - autogenerated
            'vbs'         => 'Visual Basic'          ,
            'VBS'         => 'Visual Basic'          ,
            'webinfo'     => 'ASP.Net'               ,
            'xml'         => 'XML'                   ,
            'XML'         => 'XML'                   ,
            'mxml'        => 'MXML'                  ,
            'build'       => 'NAnt scripts'          ,
            'vim'         => 'vim script'            ,
            'xaml'        => 'XAML'                  ,
            'xsd'         => 'XSD'                   ,
            'XSD'         => 'XSD'                   ,
            'xslt'        => 'XSLT'                  ,
            'XSLT'        => 'XSLT'                  ,
            'xsl'         => 'XSLT'                  ,
            'XSL'         => 'XSLT'                  ,
            'y'           => 'yacc'                  ,
            'yaml'        => 'YAML'                  ,
            'yml'         => 'YAML'                  ,
            );
# 1}}}
%{$rh_Language_by_Script}    = (                 # {{{1
            'awk'      => 'awk'                   ,
            'bash'     => 'Bourne Again Shell'    ,
            'bc'       => 'bc'                    ,# calculator
            'csh'      => 'C Shell'               ,
            'dmd'      => 'D'                     ,
            'idl'      => 'IDL'                   ,
            'kermit'   => 'Kermit'                ,
            'ksh'      => 'Korn Shell'            ,
            'lua'      => 'Lua'                   ,
            'make'     => 'make'                  ,
            'octave'   => 'Octave'                ,
            'perl5'    => 'Perl'                  ,
            'perl'     => 'Perl'                  ,
            'ruby'     => 'Ruby'                  ,
            'sed'      => 'sed'                   ,
            'sh'       => 'Bourne Shell'          ,
            'tcl'      => 'Tcl/Tk'                ,
            'tclsh'    => 'Tcl/Tk'                ,
            'tcsh'     => 'C Shell'               ,
            'wish'     => 'Tcl/Tk'                ,
            );
# 1}}}
%{$rh_Language_by_File}      = (                 # {{{1
            'Makefile'       => 'make'               ,
            'makefile'       => 'make'               ,
            'gnumakefile'    => 'make'               ,
            'Gnumakefile'    => 'make'               ,
            'CMakeLists.txt' => 'CMake'              ,
            );
# 1}}}
%{$rhaa_Filters_by_Language} = (                 # {{{1
    'ABAP'               => [   [ 'remove_matches'      , '^\*'    ], ],
    'ActionScript'       => [   
                                [ 'remove_matches'      , '^\s*//' ], 
                                [ 'call_regexp_common'  , 'C'      ],
                            ],

    'ASP'                => [   [ 'remove_matches'      , '^\s*\47'], ],  # \47 = '
    'ASP.Net'            => [   [ 'call_regexp_common'  , 'C'      ], ],
    'Ada'                => [   [ 'remove_matches'      , '^\s*--' ], ],
    'ADSO/IDSM'          => [   [ 'remove_matches'      , '^\s*\*[\+\!]' ], ],
    'AMPLE'              => [   [ 'remove_matches'      , '^\s*//' ], ],
    'Assembly'           => [  
                                [ 'remove_matches'      , '^\s*//' ],
                                [ 'remove_matches'      , '^\s*;'  ],
                                [ 'call_regexp_common'  , 'C'      ], 
                                [ 'remove_inline'       , '//.*$'  ], 
                                [ 'remove_inline'       , ';.*$'   ],
                            ],
    'awk'                => [   
                                [ 'remove_matches'      , '^\s*#'  ], 
                                [ 'remove_inline'       , '#.*$'   ],
                            ], 
    'bc'                 => [   
                                [ 'remove_matches'      , '^\s*#'  ], 
                                [ 'remove_inline'       , '#.*$'   ],
                            ], 
    'C'                  => [   
                                [ 'remove_matches'      , '^\s*//' ], # C99
                                [ 'call_regexp_common'  , 'C'      ], 
                                [ 'remove_inline'       , '//.*$'  ], # C99
                            ], 
    'C++'                => [   
                                [ 'remove_matches'      , '^\s*//' ], 
                                [ 'remove_inline'       , '//.*$'  ], 
                                [ 'call_regexp_common'  , 'C'      ],
                            ],
    'C/C++ Header'       => [   
                                [ 'remove_matches'      , '^\s*//' ], 
                                [ 'call_regexp_common'  , 'C'      ], 
                                [ 'remove_inline'       , '//.*$'  ], 
                            ],
    'CMake'              => [   
                                [ 'remove_matches'      , '^\s*#'  ],
                                [ 'remove_inline'       , '#.*$'   ], 
                            ],
    'Cython'             => [   
                                [ 'remove_matches'      , '^\s*#'  ], 
                                [ 'docstring_to_C'                 ], 
                                [ 'call_regexp_common'  , 'C'      ],
                                [ 'remove_inline'       , '#.*$'   ],
                            ], 
    'C#'                 => [   
                                [ 'remove_matches'      , '^\s*//' ], 
                                [ 'call_regexp_common'  , 'C'      ],
                                [ 'remove_inline'       , '//.*$'  ], 
                            ],
    'CCS'                => [   [ 'call_regexp_common'  , 'C'      ], ],
    'CSS'                => [   [ 'call_regexp_common'  , 'C'      ], ],
    'COBOL'              => [   [ 'remove_cobol_comments',         ], ],
    'ColdFusion'         => [   [ 'remove_html_comments',          ],
                                [ 'call_regexp_common'  , 'HTML'   ], ],
    'Crystal Reports'    => [   [ 'remove_matches'      , '^\s*//' ], ],
    'D'                  => [   
                                [ 'remove_matches'      , '^\s*//' ], 
                                [ 'call_regexp_common'  , 'C'      ],
                                [ 'remove_inline'       , '//.*$'  ], 
                            ],
    'DAL'                => [   [ 'remove_between'      , '[]',    ], ],
    'Dart'               => [   
                                [ 'remove_matches'      , '^\s*//' ], 
                                [ 'remove_inline'       , '//.*$'  ], 
                                [ 'call_regexp_common'  , 'C'      ],
                            ],
    'NASTRAN DMAP'       => [   
                                [ 'remove_matches'      , '^\s*\$' ], 
                                [ 'remove_inline'       , '\$.*$'  ], 
                            ],
    'DOS Batch'          => [   [ 'remove_matches'      , '^\s*rem', ], ],
    'DTD'                => [   [ 'remove_html_comments',          ],
                                [ 'call_regexp_common'  , 'HTML'   ], ],
    'Erlang'             => [   
                                [ 'remove_matches'      , '^\s*%'  ], 
                                [ 'remove_inline'       , '%.*$'   ],
                            ],
    'Expect'             => [   
                                [ 'remove_matches'      , '^\s*#'  ], 
                                [ 'remove_inline'       , '#.*$'   ],
                            ], 
    'Focus'              => [   [ 'remove_matches'      , '^\s*\-\*'  ], ],
    'Fortran 77'         => [   
                                [ 'remove_f77_comments' ,          ], 
                                [ 'remove_inline'       , '\!.*$'  ],
                            ],
    'Fortran 90'         => [   
                                [ 'remove_f77_comments' ,          ],
                                [ 'remove_f90_comments' ,          ], 
                                [ 'remove_inline'       , '\!.*$'  ],
                            ],
    'Fortran 95'         => [   
                                [ 'remove_f77_comments' ,          ],
                                [ 'remove_f90_comments' ,          ], 
                                [ 'remove_inline'       , '\!.*$'  ],
                            ],
    'Go'                 => [   
                                [ 'remove_matches'      , '^\s*//' ], 
                                [ 'remove_inline'       , '//.*$'  ], 
                                [ 'call_regexp_common'  , 'C'      ],
                            ],
    'Groovy'             => [   
                                [ 'remove_matches'      , '^\s*//' ], 
                                [ 'remove_inline'       , '//.*$'  ], 
                                [ 'call_regexp_common'  , 'C'      ],
                            ],
    'HTML'               => [   [ 'remove_html_comments',          ],
                                [ 'call_regexp_common'  , 'HTML'   ], ],
    'Haskell'            => [   [ 'remove_haskell_comments', '>filename<' ], ],
    'IDL'                => [   [ 'remove_matches'      , '^\s*;'  ], ],
    'JSP'                => [   [ 'remove_html_comments',          ],
                                [ 'call_regexp_common'  , 'HTML'   ],
                                [ 'remove_jsp_comments' ,          ], 
                                [ 'remove_matches'      , '^\s*//' ],
                                [ 'add_newlines'        ,          ],
                                [ 'call_regexp_common'  , 'C'      ],
                            ],
    'Java'               => [   
                                [ 'remove_matches'      , '^\s*//' ], 
                                [ 'call_regexp_common'  , 'C'      ],
                                [ 'remove_inline'       , '//.*$'  ], 
                            ],
    'Javascript'         => [   
                                [ 'remove_matches'      , '^\s*//' ], 
                                [ 'call_regexp_common'  , 'C'      ],
                                [ 'remove_inline'       , '//.*$'  ], 
                            ],
    'JCL'                => [   [ 'remove_jcl_comments' ,          ], ],
    'Lisp'               => [   [ 'remove_matches'      , '^\s*;'  ], ],
    'LiveLink OScript'   => [   [ 'remove_matches'      , '^\s*//' ], ],
#   'Lua'                => [   [ 'call_regexp_common'  , 'lua'    ], ],
    'Lua'                => [   [ 'remove_matches'      , '^\s*\-\-' ], ],
    'make'               => [   
                                [ 'remove_matches'      , '^\s*#'  ], 
                                [ 'remove_inline'       , '#.*$'   ],
                            ], 
    'MATLAB'             => [   
                                [ 'remove_matches'      , '^\s*%'  ], 
                                [ 'remove_inline'       , '%.*$'   ],
                            ], 
    'Modula3'            => [   [ 'call_regexp_common'  , 'Pascal' ], ],
        # Modula 3 comments are (* ... *) so applying the Pascal filter
        # which also treats { ... } as a comment is not really correct.
    'Objective C'        => [   
                                [ 'remove_matches'      , '^\s*//' ],
                                [ 'call_regexp_common'  , 'C'      ], 
                                [ 'remove_inline'       , '//.*$'  ], 
                            ], 
    'Objective C++'      => [   
                                [ 'remove_matches'      , '^\s*//' ],
                                [ 'call_regexp_common'  , 'C'      ], 
                                [ 'remove_inline'       , '//.*$'  ], 
                            ], 
    'Ocaml'              => [   
                                [ 'call_regexp_common'  , 'Pascal' ], 
                            ],
    'PHP/Pascal'               => [ [ 'die' ,          ], ], # never called
    'MATLAB/Objective C/MUMPS' => [ [ 'die' ,          ], ], # never called
    'MUMPS'              => [   [ 'remove_matches'      , '^\s*;'  ], ], 
    'Octave'             => [   
                                [ 'remove_matches'      , '^\s*#'  ], 
                                [ 'remove_inline'       , '#.*$'   ],
                            ], 
    'Oracle Forms'       => [   [ 'call_regexp_common'  , 'C'      ], ],
    'Oracle Reports'     => [   [ 'call_regexp_common'  , 'C'      ], ],
    'Pascal'             => [   
                                [ 'call_regexp_common'  , 'Pascal' ], 
                                [ 'remove_matches'      , '^\s*//' ],
                            ],
    'Patran Command Language'=> [   
                                [ 'remove_matches'      , '^\s*#'   ], 
                                [ 'remove_matches'      , '^\s*\$#' ], 
                                [ 'call_regexp_common'  , 'C'       ],
                            ],
    'Perl'               => [   [ 'remove_below'        , '^__(END|DATA)__'],
                                [ 'remove_matches'      , '^\s*#'  ], 
                                [ 'remove_below_above'  , '^=head1', '^=cut'  ], 
                                [ 'remove_inline'       , '#.*$'   ],
                            ], 
    'Python'             => [   
                                [ 'remove_matches'      , '^\s*#'  ], 
                                [ 'docstring_to_C'                 ], 
                                [ 'call_regexp_common'  , 'C'      ],
                                [ 'remove_inline'       , '#.*$'   ],
                            ], 
    'PHP'                => [   
                                [ 'remove_matches'      , '^\s*#'  ],
                                [ 'remove_matches'      , '^\s*//' ], 
                                [ 'call_regexp_common'  , 'C'      ], 
                                [ 'remove_inline'       , '#.*$'   ],
                                [ 'remove_inline'       , '//.*$'  ],
                            ],
    'Rexx'               => [   [ 'call_regexp_common'  , 'C'      ], ],
    'Ruby'               => [   
                                [ 'remove_matches'      , '^\s*#'  ], 
                                [ 'remove_inline'       , '#.*$'   ],
                            ], 
    'Ruby HTML'          => [   [ 'remove_html_comments',          ],
                                [ 'call_regexp_common'  , 'HTML'   ], ],
    'Scala'              => [   
                                [ 'remove_matches'      , '^\s*//' ], 
                                [ 'remove_inline'       , '//.*$'  ], 
                                [ 'call_regexp_common'  , 'C'      ],
                            ],
    'SKILL'              => [   
                                [ 'call_regexp_common'  , 'C'      ], 
                                [ 'remove_matches'      , '^\s*;'  ],
                            ],
    'SKILL++'            => [   
                                [ 'call_regexp_common'  , 'C'      ], 
                                [ 'remove_matches'      , '^\s*;'  ],
                            ],
    'SQL'                => [   
                                [ 'call_regexp_common'  , 'C'      ], 
                                [ 'remove_matches'      , '^\s*--' ],
                                [ 'remove_inline'       , '--.*$'  ],
                            ],
    'SQL Stored Procedure'=> [   
                                [ 'call_regexp_common'  , 'C'      ], 
                                [ 'remove_matches'      , '^\s*--' ],
                                [ 'remove_inline'       , '--.*$'  ],
                            ],
    'SQL Data'           => [   
                                [ 'call_regexp_common'  , 'C'      ], 
                                [ 'remove_matches'      , '^\s*--' ],
                                [ 'remove_inline'       , '--.*$'  ],
                            ],
    'sed'                => [   
                                [ 'remove_matches'      , '^\s*#'  ], 
                                [ 'remove_inline'       , '#.*$'   ],
                            ], 
    'Smarty'             => [   
                                [ 'smarty_to_C'                    ], 
                                [ 'call_regexp_common'  , 'C'      ],
                            ], 
    'Bourne Again Shell' => [   
                                [ 'remove_matches'      , '^\s*#'  ], 
                                [ 'remove_inline'       , '#.*$'   ],
                            ], 
    'Bourne Shell'       => [   
                                [ 'remove_matches'      , '^\s*#'  ], 
                                [ 'remove_inline'       , '#.*$'   ],
                            ], 
    'm4'                 => [   [ 'remove_matches'      , '^dnl '  ], ], 
    'C Shell'            => [   
                                [ 'remove_matches'      , '^\s*#'  ], 
                                [ 'remove_inline'       , '#.*$'   ],
                            ], 
    'Kermit'             => [  
                                [ 'remove_matches'      , '^\s*#'  ], 
                                [ 'remove_matches'      , '^\s*;'  ], 
                                [ 'remove_inline'       , '#.*$'   ],
                            ], 
    'Korn Shell'         => [   
                                [ 'remove_matches'      , '^\s*#'  ], 
                                [ 'remove_inline'       , '#.*$'   ],
                            ], 
    'Tcl/Tk'             => [   
                                [ 'remove_matches'      , '^\s*#'  ], 
                                [ 'remove_inline'       , '#.*$'   ],
                            ], 
    'Teamcenter def'     => [   [ 'remove_matches'      , '^\s*#'  ], ], 
    'Teamcenter met'     => [   [ 'call_regexp_common'  , 'C'      ], ],
    'Teamcenter mth'     => [   [ 'remove_matches'      , '^\s*#'  ], ], 
    'Softbridge Basic'   => [   [ 'remove_above'        , '^\s*Attribute\s+VB_Name\s+=' ],               
                                [ 'remove_matches'      , '^\s*Attribute\s+'],
                                [ 'remove_matches'      , '^\s*\47'], ],  # \47 = '
    # http://www.altium.com/files/learningguides/TR0114%20VHDL%20Language%20Reference.pdf
    'VHDL'               => [   
                                [ 'remove_matches'      , '^\s*--' ],
                                [ 'remove_matches'      , '^\s*//' ], 
                                [ 'call_regexp_common'  , 'C'      ], 
                                [ 'remove_inline'       , '--.*$'  ],
                                [ 'remove_inline'       , '//.*$'  ], 
                            ],
    'vim script'         => [   
                                [ 'remove_matches'      , '^\s*"'  ], 
                                [ 'remove_inline'       , '".*$'   ], 
                            ],
    'Visual Basic'       => [   [ 'remove_above'        , '^\s*Attribute\s+VB_Name\s+=' ],               
                                [ 'remove_matches'      , '^\s*Attribute\s+'],
                                [ 'remove_matches'      , '^\s*\47'], ],  # \47 = '
    'yacc'               => [   [ 'call_regexp_common'  , 'C'      ], ],
    'YAML'               => [   
                                [ 'remove_matches'      , '^\s*#'  ], 
                                [ 'remove_inline'       , '#.*$'   ], 
                            ],
    'lex'                => [   [ 'call_regexp_common'  , 'C'      ], ],
    'XAML'               => [   [ 'remove_html_comments',          ],
                                [ 'call_regexp_common'  , 'HTML'   ], ],
    'MXML'               => [   [ 'remove_html_comments',          ],
                                [ 'call_regexp_common'  , 'HTML'   ], ],
    'XML'                => [   [ 'remove_html_comments',          ],
                                [ 'call_regexp_common'  , 'HTML'   ], ],
    'XSD'                => [   [ 'remove_html_comments',          ],
                                [ 'call_regexp_common'  , 'HTML'   ], ],
    'XSLT'               => [   [ 'remove_html_comments',          ],
                                [ 'call_regexp_common'  , 'HTML'   ], ],
    'NAnt scripts'       => [   [ 'remove_html_comments',          ],
                                [ 'call_regexp_common'  , 'HTML'   ], ],
    'MSBuild scripts'    => [   [ 'remove_html_comments',          ],
                                [ 'call_regexp_common'  , 'HTML'   ], ],
    );
# 1}}}
%{$rh_EOL_continuation_re} = (                 # {{{1
    'ActionScript'       =>     '\\\\$'         ,
    'Assembly'           =>     '\\\\$'         ,
    'ASP'                =>     '\\\\$'         ,
    'ASP.Net'            =>     '\\\\$'         ,
    'Ada'                =>     '\\\\$'         ,
    'awk'                =>     '\\\\$'         ,
    'bc'                 =>     '\\\\$'         ,
    'C'                  =>     '\\\\$'         ,
    'C++'                =>     '\\\\$'         ,
    'C/C++ Header'       =>     '\\\\$'         ,
    'CMake'              =>     '\\\\$'         ,
    'Cython'             =>     '\\\\$'         ,
    'C#'                 =>     '\\\\$'         ,
    'D'                  =>     '\\\\$'         ,
    'Dart'               =>     '\\\\$'         ,
    'Expect'             =>     '\\\\$'         ,
    'Go'                 =>     '\\\\$'         ,
    'Java'               =>     '\\\\$'         ,
    'Javascript'         =>     '\\\\$'         ,
    'Lua'                =>     '\\\\$'         ,
    'make'               =>     '\\\\$'         ,
    'MATLAB'             =>     '\.\.\.\s*$'    ,
    'Objective C'        =>     '\\\\$'         ,
    'Objective C++'      =>     '\\\\$'         ,
    'Ocaml'              =>     '\\\\$'         ,
    'Octave'             =>     '\.\.\.\s*$'    ,
    'Patran Command Language'=> '\\\\$'         ,
    'Python'             =>     '\\\\$'         ,
    'Ruby'               =>     '\\\\$'         ,
    'sed'                =>     '\\\\$'         ,
    'Bourne Again Shell' =>     '\\\\$'         ,
    'Bourne Shell'       =>     '\\\\$'         ,
    'C Shell'            =>     '\\\\$'         ,
    'Kermit'             =>     '\\\\$'         ,
    'Korn Shell'         =>     '\\\\$'         ,
    'Tcl/Tk'             =>     '\\\\$'         ,
    'lex'                =>     '\\\\$'         ,
    );
# 1}}}
%{$rh_Not_Code_Extension}    = (                 # {{{1
   '1'       => 1,  # Man pages (documentation):
   '2'       => 1,
   '3'       => 1,
   '4'       => 1,
   '5'       => 1,
   '6'       => 1,
   '7'       => 1,
   '8'       => 1,
   '9'       => 1,
   'a'       => 1,  # Static object code.
   'ad'      => 1,  # X application default resource file.
   'afm'     => 1,  # font metrics
   'arc'     => 1,  # arc(1) archive
   'arj'     => 1,  # arj(1) archive
   'au'      => 1,  # Audio sound filearj(1) archive
   'bak'     => 1,  # Backup files - we only want to count the "real" files.
   'bdf'     => 1,
   'bmp'     => 1,
   'bz2'     => 1,  # bzip2(1) compressed file
   'csv'     => 1,  # comma separated values
   'desktop' => 1,
   'dic'     => 1,
   'doc'     => 1,
   'elc'     => 1,
   'eps'     => 1,
   'fig'     => 1,
   'gif'     => 1,
   'gz'      => 1,
   'hdf'     => 1,  # hierarchical data format
   'in'      => 1,  # Debatable.
   'jpg'     => 1,
   'kdelnk'  => 1,
   'man'     => 1,
   'mf'      => 1,
   'mp3'     => 1,
   'n'       => 1,
   'o'       => 1,  # Object code is generated from source code.
   'pbm'     => 1,
   'pdf'     => 1,
   'pfb'     => 1,
   'png'     => 1,
   'po'      => 1,
   'ps'      => 1,  # Postscript is _USUALLY_ generated automatically.
   'sgm'     => 1,
   'sgml'    => 1,
   'so'      => 1,  # Dynamically-loaded object code.
   'Tag'     => 1,
   'tex'     => 1,
   'text'    => 1,
   'tfm'     => 1,
   'tgz'     => 1,  # gzipped tarball
   'tiff'    => 1,
   'txt'     => 1, 
   'vf'      => 1,
   'wav'     => 1,
   'xbm'     => 1,
   'xpm'     => 1,
   'Y'       => 1,  # file compressed with "Yabba"
   'Z'       => 1,  # file compressed with "compress"
   'zip'     => 1,  # zip archive
); # 1}}}
%{$rh_Not_Code_Filename}     = (                 # {{{1
   'AUTHORS'     => 1,
   'BUGS'        => 1,
   'BUGS'        => 1,
   'Changelog'   => 1,
   'ChangeLog'   => 1,
   'ChangeLog'   => 1,
   'Changes'     => 1,
   'CHANGES'     => 1,
   'COPYING'     => 1,
   'COPYING'     => 1,
   '.cvsignore'  => 1,
   'Entries'     => 1,
   'FAQ'         => 1,
   'iconfig.h'   => 1, # Skip "iconfig.h" files; they're used in Imakefiles.
   'INSTALL'     => 1,
   'MAINTAINERS' => 1,
   'MD5SUMS'     => 1,
   'NEWS'        => 1,
   'readme'      => 1,
   'Readme'      => 1,
   'README'      => 1,
   'README.tk'   => 1, # used in kdemultimedia, it's confusing.
   'Repository'  => 1,
   'Root'        => 1, # CVS
   'TODO'        => 1,
);
# 1}}}
%{$rh_Scale_Factor}          = (                 # {{{1
    '1032/af'                      =>   5.00,
    '1st generation default'       =>   0.25,
    '2nd generation default'       =>   0.75,
    '3rd generation default'       =>   1.00,
    '4th generation default'       =>   4.00,
    '5th generation default'       =>  16.00,
    'aas macro'                    =>   0.88,
    'abap/4'                       =>   5.00,
    'ABAP'                         =>   5.00,
    'accel'                        =>   4.21,
    'access'                       =>   2.11,
    'ActionScript'                 =>   1.36,
    'actor'                        =>   3.81,
    'acumen'                       =>   2.86,
    'Ada'                          =>   0.52,
    'Ada 83'                       =>   1.13,
    'Ada 95'                       =>   1.63,
    'adr/dl'                       =>   2.00,
    'adr/ideal/pdl'                =>   4.00,
    'ads/batch'                    =>   4.00,
    'ads/online'                   =>   4.00,
    'ADSO/IDSM'                    =>   3.00,
    'advantage'                    =>   2.11,
    'ai shell default'             =>   1.63,
    'ai shells'                    =>   1.63,
    'algol 68'                     =>   0.75,
    'algol w'                      =>   0.75,
    'ambush'                       =>   2.50,
    'aml'                          =>   1.63,
    'AMPLE'                        =>   2.00,
    'amppl ii'                     =>   1.25,
    'ansi basic'                   =>   1.25,
    'ansi cobol 74'                =>   0.75,
    'ansi cobol 85'                =>   0.88,
    'SQL'                          =>   6.15,
    'SQL Stored Procedure'         =>   6.15,
    'SQL Data'                     =>   1.00,
    'answer/db'                    =>   6.15,
    'apl 360/370'                  =>   2.50,
    'apl default'                  =>   2.50,
    'apl*plus'                     =>   2.50,
    'applesoft basic'              =>   0.63,
    'application builder'          =>   4.00,
    'application manager'          =>   2.22,
    'aps'                          =>   0.96,
    'aps'                          =>   4.71,
    'apt'                          =>   1.13,
    'aptools'                      =>   4.00,
    'arc'                          =>   1.63,
    'ariel'                        =>   0.75,
    'arity'                        =>   1.63,
    'arity prolog'                 =>   1.25,
    'art'                          =>   1.63,
    'art enterprise'               =>   1.74,
    'artemis'                      =>   2.00,
    'artim'                        =>   1.74,
    'as/set'                       =>   4.21,
    'asi/inquiry'                  =>   6.15,
    'ask windows'                  =>   1.74,
'asa'                         =>   1.29,
'ASP'                         =>   1.29,
'ASP.Net'                     =>   1.29,
'aspx'                        =>   1.29,
#'resx'                        =>   1.29,
'asax'                        =>   1.29,
'ascx'                        =>   1.29,
'asmx'                        =>   1.29,
'config'                      =>   1.29,
'webinfo'                     =>   1.29,
'CCS'                         =>   5.33,

#   'assembler (basic)'            =>   0.25,
    'Assembly'                     =>   0.25,

    'Assembly (macro)'             =>   0.51,
    'associative default'          =>   1.25,
    'autocoder'                    =>   0.25,
    'awk'                          =>   3.81,
    'aztec c'                      =>   0.63,
    'balm'                         =>   0.75,
    'base sas'                     =>   1.51,
    'basic'                        =>   0.75,
    'basic a'                      =>   0.63,
#   'basic assembly'               =>   0.25,
    'bc'                           =>   1.50,
    'berkeley pascal'              =>   0.88,
    'better basic'                 =>   0.88,
    'bliss'                        =>   0.75,
    'bmsgen'                       =>   2.22,
    'boeingcalc'                   =>  13.33,
    'bteq'                         =>   6.15,

    'C'                            =>   0.77,

    'c set 2'                      =>   0.88,

    'C#'                           =>   1.36,

    'C++'                          =>   1.51,

    'c86plus'                      =>   0.63,
    'cadbfast'                     =>   2.00,
    'caearl'                       =>   2.86,
    'cast'                         =>   1.63,
    'cbasic'                       =>   0.88,
    'cdadl'                        =>   4.00,
    'cellsim'                      =>   1.74,
'ColdFusion'               =>   4.00,
    'chili'                        =>   0.75,
    'chill'                        =>   0.75,
    'cics'                         =>   1.74,
    'clarion'                      =>   1.38,
    'clascal'                      =>   1.00,
    'cli'                          =>   2.50,
    'clipper'                      =>   2.05,
    'clipper db'                   =>   2.00,
    'clos'                         =>   3.81,
    'clout'                        =>   2.00,
    'CMake'                        =>   1.00,
    'cms2'                         =>   0.75,
    'cmsgen'                       =>   4.21,
    'COBOL'                        =>   1.04,
    'COBOL ii'                     =>   0.75,
    'COBOL/400'                    =>   0.88,
    'cobra'                        =>   4.00,
    'codecenter'                   =>   2.22,
    'cofac'                        =>   2.22,
    'cogen'                        =>   2.22,
    'cognos'                       =>   2.22,
    'cogo'                         =>   1.13,
    'comal'                        =>   1.00,
    'comit ii'                     =>   1.25,
    'common lisp'                  =>   1.25,
    'concurrent pascal'            =>   1.00,
    'conniver'                     =>   1.25,
    'cool:gen/ief'                 =>   2.58,
    'coral 66'                     =>   0.75,
    'corvet'                       =>   4.21,
    'corvision'                    =>   5.33,
    'cpl'                          =>   0.50,
    'Crystal Reports'              =>   4.00,
    'csl'                          =>   1.63,
    'csp'                          =>   1.51,
    'cssl'                         =>   1.74,
    
'CSS' => 1.0,
    
    'culprit'                      =>   1.57,
    'cxpert'                       =>   1.63,
    'cygnet'                       =>   4.21,
    'D'                            =>   1.70,
    'DAL'                          =>   1.50,
    'Dart'                         =>   2.00,
    'data base default'            =>   2.00,
    'dataflex'                     =>   2.00,
    'datatrieve'                   =>   4.00,
    'dbase iii'                    =>   2.00,
    'dbase iv'                     =>   1.54,
    'dcl'                          =>   0.38,
    'decision support default'     =>   2.22,
    'decrally'                     =>   2.00,
    'delphi'                       =>   2.76,
    'dl/1'                         =>   2.00,
    'NASTRAN DMAP'                 =>   2.35,
    'dna4'                         =>   4.21,
    'DOS Batch'                    =>   0.63,
    'dsp assembly'                 =>   0.50,
    'dtabl'                        =>   1.74,
    'dtipt'                        =>   1.74,
    'dyana'                        =>   1.13,
    'dynamoiii'                    =>   1.74,
    'easel'                        =>   2.76,
    'easy'                         =>   1.63,
    'easytrieve+'                  =>   2.35,
    'eclipse'                      =>   1.63,
    'eda/sql'                      =>   6.67,
    'edscheme 3.4'                 =>   1.51,
    'eiffel'                       =>   3.81,
    'enform'                       =>   1.74,
    'englishbased default'         =>   1.51,
    'ensemble'                     =>   2.76,
    'epos'                         =>   4.00,
    'Erlang'                       =>   2.11,
    'esf'                          =>   2.00,
    'espadvisor'                   =>   1.63,
    'espl/i'                       =>   1.13,
    'euclid'                       =>   0.75,
    'excel'                        =>   1.74,
    'excel 12'                     =>  13.33,
    'excel 34'                     =>  13.33,
    'excel 5'                      =>  13.33,
    'express'                      =>   2.22,
    'exsys'                        =>   1.63,
    'extended common lisp'         =>   1.43,
    'eznomad'                      =>   2.22,
    'facets'                       =>   4.00,
    'factorylink iv'               =>   2.76,
    'fame'                         =>   2.22,
    'filemaker pro'                =>   2.22,
    'flavors'                      =>   2.76,
    'flex'                         =>   1.74,
    'flexgen'                      =>   2.76,
    'Focus'                        =>   1.90,
    'foil'                         =>   1.51,
    'forte'                        =>   4.44,
    'forth'                        =>   1.25,
    'Fortran 66'                   =>   0.63,
    'Fortran 77'                   =>   0.75,
    'Fortran 90'                   =>   1.00,
    'Fortran 95'                   =>   1.13,
    'Fortran II'                   =>   0.63,
    'foundation'                   =>   2.76,
    'foxpro'                       =>   2.29,
    'foxpro 1'                     =>   2.00,
    'foxpro 2.5'                   =>   2.35,
    'framework'                    =>  13.33,
    'g2'                           =>   1.63,
    'gamma'                        =>   5.00,
    'genascript'                   =>   2.96,
    'gener/ol'                     =>   6.15,
    'genexus'                      =>   5.33,
    'genifer'                      =>   4.21,
    'geode 2.0'                    =>   5.00,
    'gfa basic'                    =>   2.35,
    'gml'                          =>   1.74,
    'golden common lisp'           =>   1.25,
    'gpss'                         =>   1.74,
    'guest'                        =>   2.86,
    'guru'                         =>   1.63,
    'Go'                           =>   2.50,
    'Groovy'                       =>   4.10,
    'gw basic'                     =>   0.82,
    'Haskell'                      =>   2.11,
    'high c'                       =>   0.63,
    'hlevel'                       =>   1.38,
    'hp basic'                     =>   0.63,

'HTML'          => 1.90 ,
'XML'           => 1.90 ,
'MXML'          => 1.90 ,
'XSLT'          => 1.90 ,
'DTD'           => 1.90 ,
'XSD'           => 1.90 ,
'NAnt scripts'    => 1.90 ,
'MSBuild scripts' => 1.90 , 

    'HTML 2'                       =>   5.00,
    'HTML 3'                       =>   5.33,
    'huron'                        =>   5.00,
    'ibm adf i'                    =>   4.00,
    'ibm adf ii'                   =>   4.44,
    'ibm advanced basic'           =>   0.82,
    'ibm cics/vs'                  =>   2.00,
    'ibm compiled basic'           =>   0.88,
    'ibm vs cobol'                 =>   0.75,
    'ibm vs cobol ii'              =>   0.88,
    'ices'                         =>   1.13,
    'icon'                         =>   1.00,
    'ideal'                        =>   1.54,
    'idms'                         =>   2.00,
    'ief'                          =>   5.71,
    'ief/cool:gen'                 =>   2.58,
    'iew'                          =>   5.71,
    'ifps/plus'                    =>   2.50,
    'imprs'                        =>   2.00,
    'informix'                     =>   2.58,
    'ingres'                       =>   2.00,
    'inquire'                      =>   6.15,
    'insight2'                     =>   1.63,
    'install/1'                    =>   5.00,
    'intellect'                    =>   1.51,
    'interlisp'                    =>   1.38,
    'interpreted basic'            =>   0.75,
    'interpreted c'                =>   0.63,
    'iqlisp'                       =>   1.38,
    'iqrp'                         =>   6.15,
    'j2ee'                         =>   1.60,
    'janus'                        =>   1.13,
    'Java'                         =>   1.36,
'Javascript'                   =>   1.48,
'JSP'                          =>   1.48,
    'JCL'                          =>   1.67,
    'joss'                         =>   0.75,
    'jovial'                       =>   0.75,
    'jsp'                          =>   1.36,
    'kappa'                        =>   2.00,
    'kbms'                         =>   1.63,
    'kcl'                          =>   1.25,
    'kee'                          =>   1.63,
    'keyplus'                      =>   2.00,
    'kl'                           =>   1.25,
    'klo'                          =>   1.25,
    'knowol'                       =>   1.63,
    'krl'                          =>   1.38,
    'Kermit'                       =>   2.00,
    'Korn Shell'                   =>   3.81,
    'ladder logic'                 =>   2.22,
    'lambit/l'                     =>   1.25,
    'lattice c'                    =>   0.63,
    'liana'                        =>   0.63,
    'lilith'                       =>   1.13,
    'linc ii'                      =>   5.71,
    'Lisp'                         =>   1.25,
    'LiveLink OScript'             =>   3.5 ,
    'loglisp'                      =>   1.38,
    'loops'                        =>   3.81,
    'lotus 123 dos'                =>  13.33,
    'lotus macros'                 =>   0.75,
    'lotus notes'                  =>   3.64,
    'lucid 3d'                     =>  13.33,
    'lyric'                        =>   1.51,
    'm4'                           =>   1.00,
    'm'                            =>   5.00,
    'macforth'                     =>   1.25,
    'mach1'                        =>   2.00,
    'machine language'             =>   0.13,
    'maestro'                      =>   5.00,
    'magec'                        =>   5.00,
    'magik'                        =>   3.81,
    'Lake'                         =>   3.81,
    'make'                         =>   2.50,
    'mantis'                       =>   2.96,
    'mapper'                       =>   0.99,
    'mark iv'                      =>   2.00,
    'mark v'                       =>   2.22,
    'mathcad'                      =>  16.00,
    'mdl'                          =>   2.22,
    'mentor'                       =>   1.51,
    'mesa'                         =>   0.75,
    'microfocus cobol'             =>   1.00,
    'microforth'                   =>   1.25,
    'microsoft c'                  =>   0.63,
    'microstep'                    =>   4.00,
    'miranda'                      =>   2.00,
    'model 204'                    =>   2.11,
    'modula 2'                     =>   1.00,
    'mosaic'                       =>  13.33,
    # 'ms c ++ v. 7'                 =>   1.51,
    'ms compiled basic'            =>   0.88,
    'msl'                          =>   1.25,
    'mulisp'                       =>   1.25,
    'MUMPS'                        =>   4.21,
    'Nastran'                      =>   1.13,
    'natural'                      =>   1.54,
    'natural 1'                    =>   1.51,
    'natural 2'                    =>   1.74,
    'natural construct'            =>   3.20,
    'natural language'             =>   0.03,
    'netron/cap'                   =>   4.21,
    'nexpert'                      =>   1.63,
    'nial'                         =>   1.63,
    'nomad2'                       =>   2.00,
    'nonprocedural default'        =>   2.22,
    'notes vip'                    =>   2.22,
    'nroff'                        =>   1.51,
    'object assembler'             =>   1.25,
    'object lisp'                  =>   2.76,
    'object logo'                  =>   2.76,
    'object pascal'                =>   2.76,
    'object star'                  =>   5.00,
    'Objective C'                  =>   2.96,
    'Objective C++'                =>   2.96,
    'objectoriented default'       =>   2.76,
    'objectview'                   =>   3.20,
    'Ocaml'                        =>   3.00,
    'ogl'                          =>   1.00,
    'omnis 7'                      =>   2.00,
    'oodl'                         =>   2.76,
    'ops'                          =>   1.74,
    'ops5'                         =>   1.38,
    'oracle'                       =>   2.76,
    'Oracle Reports'               =>   2.76,
    'Oracle Forms'                 =>   2.67,
    'Oracle Developer/2000'        =>   3.48,
    'oscar'                        =>   0.75,
    'pacbase'                      =>   1.67,
    'pace'                         =>   2.00,
    'paradox/pal'                  =>   2.22,
    'Pascal'                       =>   0.88,
    'Patran Command Language'      =>   2.50,
    'pc focus'                     =>   2.22,
    'pdl millenium'                =>   3.81,
    'pdp11 ade'                    =>   1.51,
    'peoplesoft'                   =>   2.50,
    'Perl'                         =>   4.00,
    'persistance object builder'   =>   3.81,
    'pilot'                        =>   1.51,
    'pl/1'                         =>   1.38,
    'pl/m'                         =>   1.13,
    'pl/s'                         =>   0.88,
    'pl/sql'                       =>   2.58,
    'planit'                       =>   1.51,
    'planner'                      =>   1.25,
    'planperfect 1'                =>  11.43,
    'plato'                        =>   1.51,
    'polyforth'                    =>   1.25,
    'pop'                          =>   1.38,
    'poplog'                       =>   1.38,
    'power basic'                  =>   1.63,
    'powerbuilder'                 =>   3.33,
    'powerhouse'                   =>   5.71,
    'ppl (plus)'                   =>   2.00,
    'problemoriented default'      =>   1.13,
    'proc'                         =>   2.96,
    'procedural default'           =>   0.75,
    'professional pascal'          =>   0.88,
    'program generator default'    =>   5.00,
    'progress v4'                  =>   2.22,
    'proiv'                        =>   1.38,
    'prolog'                       =>   1.25,
    'prose'                        =>   0.75,
    'proteus'                      =>   0.75,
    'qbasic'                       =>   1.38,
    'qbe'                          =>   6.15,
    'qmf'                          =>   5.33,
    'qnial'                        =>   1.63,
    'quattro'                      =>  13.33,
    'quattro pro'                  =>  13.33,
    'query default'                =>   6.15,
    'quick basic 1'                =>   1.25,
    'quick basic 2'                =>   1.31,
    'quick basic 3'                =>   1.38,
    'quick c'                      =>   0.63,
    'quickbuild'                   =>   2.86,
    'quiz'                         =>   5.33,
    'rally'                        =>   2.00,
    'ramis ii'                     =>   2.00,
    'rapidgen'                     =>   2.86,
    'ratfor'                       =>   0.88,
    'rdb'                          =>   2.00,
    'realia'                       =>   1.74,
    'realizer 1.0'                 =>   2.00,
    'realizer 2.0'                 =>   2.22,
    'relate/3000'                  =>   2.00,
    'reuse default'                =>  16.00,
    'Rexx'                         =>   1.19,
    'Rexx (mvs)'                   =>   1.00,
    'Rexx (os/2)'                  =>   1.74,
    'rm basic'                     =>   0.88,
    'rm cobol'                     =>   0.75,
    'rm fortran'                   =>   0.75,
    'rpg i'                        =>   1.00,
    'rpg ii'                       =>   1.63,
    'rpg iii'                      =>   1.63,
    'rtexpert 1.4'                 =>   1.38,
    'sabretalk'                    =>   0.90,
    'sail'                         =>   0.75,
    'sapiens'                      =>   5.00,
    'sas'                          =>   1.95,
    'savvy'                        =>   6.15,
    'sbasic'                       =>   0.88,
    'Scala'                        =>   4.10,
    'sceptre'                      =>   1.13,
    'scheme'                       =>   1.51,
    'screen painter default'       =>  13.33,
    'sequal'                       =>   6.67,
    'Bourne Shell'                 =>   3.81,
    'Bourne Again Shell'           =>   3.81,
    'ksh'                          =>   3.81,
    'C Shell'                      =>   3.81,
    'siebel tools '                =>   6.15,
    'simplan'                      =>   2.22,
    'simscript'                    =>   1.74,
    'simula'                       =>   1.74,
    'simula 67'                    =>   1.74,
    'simulation default'           =>   1.74,
    'SKILL'                        =>   2.00,
    'SKILL++'                      =>   2.00,
    'slogan'                       =>   0.98,
    'smalltalk'                    =>   2.50,
    'smalltalk 286'                =>   3.81,
    'smalltalk 80'                 =>   3.81,
    'smalltalk/v'                  =>   3.81,
    'Smarty'                       =>   3.50,
    'snap'                         =>   1.00,
    'snobol24'                     =>   0.63,
    'softscreen'                   =>   5.71,
    'Softbridge Basic'             =>   2.76,
    'solo'                         =>   1.38,
    'speakeasy'                    =>   2.22,
    'spinnaker ppl'                =>   2.22,
    'splus'                        =>   2.50,
    'spreadsheet default'          =>  13.33,
    'sps'                          =>   0.25,
    'spss'                         =>   2.50,
    'SQL'                          =>   2.29,
    'sqlwindows'                   =>   6.67,
    'statistical default'          =>   2.50,
    'strategem'                    =>   2.22,
    'stress'                       =>   1.13,
    'strongly typed default'       =>   0.88,
    'style'                        =>   1.74,
    'superbase 1.3'                =>   2.22,
    'surpass'                      =>  13.33,
    'sybase'                       =>   2.00,
    'symantec c++'                 =>   2.76,
    'symbolang'                    =>   1.25,
    'synchroworks'                 =>   4.44,
    'synon/2e'                     =>   4.21,
    'systemw'                      =>   2.22,
    'tandem access language'       =>   0.88,
    'Tcl/Tk'                       =>   4.00,
    'Teamcenter def'               =>   1.00,
    'Teamcenter met'               =>   1.00,
    'Teamcenter mth'               =>   1.00,
    'telon'                        =>   5.00,
    'tessaract'                    =>   2.00,
    'the twin'                     =>  13.33,
    'themis'                       =>   6.15,
    'tiief'                        =>   5.71,
    'topspeed c++'                 =>   2.76,
    'transform'                    =>   5.33,
    'translisp plus'               =>   1.43,
    'treet'                        =>   1.25,
    'treetran'                     =>   1.25,
    'trs80 basic'                  =>   0.63,
    'true basic'                   =>   1.25,
    'turbo c'                      =>   0.63,
    # 'turbo c++'                    =>   1.51,
    'turbo expert'                 =>   1.63,
    'turbo pascal >5'              =>   1.63,
    'turbo pascal 14'              =>   1.00,
    'turbo pascal 45'              =>   1.13,
    'turbo prolog'                 =>   1.00,
    'turing'                       =>   1.00,
    'tutor'                        =>   1.51,
    'twaice'                       =>   1.63,
    'ucsd pascal'                  =>   0.88,
    'ufo/ims'                      =>   2.22,
    'uhelp'                        =>   2.50,
    'uniface'                      =>   5.00,
    # 'unix shell scripts'           =>   3.81,
    'vax acms'                     =>   1.38,
    'vax ade'                      =>   2.00,
    'vbscript'                     =>   2.35,
    'vectran'                      =>   0.75,
    'VHDL'                         =>   4.21,
    'vim script'                   =>   3.00,
    'visible c'                    =>   1.63,
    'visible cobol'                =>   2.00,
    'visicalc 1'                   =>   8.89,
    'visual 4.0'                   =>   2.76,
    'visual basic'                 =>   1.90,
    'visual basic 1'               =>   1.74,
    'visual basic 2'               =>   1.86,
    'visual basic 3'               =>   2.00,
    'visual basic 4'               =>   2.22,
    'visual basic 5'               =>   2.76,
    'Visual Basic'                 =>   2.76,
    'visual basic dos'             =>   2.00,
    'visual c++'                   =>   2.35,
    'visual cobol'                 =>   4.00,
    'visual objects'               =>   5.00,
    'visualage'                    =>   3.81,
    'visualgen'                    =>   4.44,
    'vpf'                          =>   0.84,
    'vsrexx'                       =>   2.50,
    'vulcan'                       =>   1.25,
    'vz programmer'                =>   2.22,
    'warp x'                       =>   2.00,
    'watcom c'                     =>   0.63,
    'watcom c/386'                 =>   0.63,
    'waterloo c'                   =>   0.63,
    'waterloo pascal'              =>   0.88,
    'watfiv'                       =>   0.94,
    'watfor'                       =>   0.88,
    'web scripts'                  =>   5.33,
    'whip'                         =>   0.88,
    'wizard'                       =>   2.86,
    'xlisp'                        =>   1.25,
    'XAML'                         =>   1.90,
    'yacc'                         =>   1.51,
    'yacc++'                       =>   1.51,
    'YAML'                         =>   0.90,
    'zbasic'                       =>   0.88,
    'zim'                          =>   4.21,
    'zlisp'                        =>   1.25,

'Expect'  => 2.00,
'C/C++ Header'  => 1.00, 
'inc'     => 1.00,
'lex'     => 1.00,
'MATLAB'  => 4.00,
'IDL'     => 3.80,
'Octave'  => 4.00,
'ML'      => 3.00,
'Modula3' => 2.00,
'PHP'     => 3.50,
'Python'  => 4.20,
'Cython'  => 3.80,
'Ruby'    => 4.20,
'Ruby HTML' => 4.00,
'sed'     => 4.00,
'Lua'     => 4.00,
);
# 1}}}
%{$rh_Known_Binary_Archives} = (                 # {{{1
            '.tar'     => 1 ,
            '.tar.Z'   => 1 ,
            '.tar.gz'  => 1 ,
            '.tar.bz2' => 1 ,
            '.zip'     => 1 ,
            '.Zip'     => 1 ,
            '.ZIP'     => 1 ,
            '.ear'     => 1 ,  # Java
            '.war'     => 1 ,  # contained within .ear
            );
# 1}}}
} # end sub set_constants()
sub Install_Regexp_Common {                  # {{{1
    # Installs portions of Damian Conway's & Abigail's Regexp::Common
    # module, v2.120, into a temporary directory for the duration of
    # this run.

    my %Regexp_Common_Contents = ();
$Regexp_Common_Contents{'Common'} = <<'EOCommon'; # {{{2
package Regexp::Common;

use 5.00473;
use strict;

local $^W = 1;

use vars qw /$VERSION %RE %sub_interface $AUTOLOAD/;

($VERSION) = q $Revision: 2.120 $ =~ /([\d.]+)/;


sub _croak {
    require Carp;
    goto &Carp::croak;
}

sub _carp {
    require Carp;
    goto &Carp::carp;
}

sub new {
    my ($class, @data) = @_;
    my %self;
    tie %self, $class, @data;
    return \%self;
}

sub TIEHASH {
    my ($class, @data) = @_;
    bless \@data, $class;
}

sub FETCH {
    my ($self, $extra) = @_;
    return bless ref($self)->new(@$self, $extra), ref($self);
}

# Modification for cloc:  only need a few modules from Regexp::Common.
my %imports = map {$_ => "Regexp::Common::$_"}
              qw /balanced comment delimited /;
#my %imports = map {$_ => "Regexp::Common::$_"}
#              qw /balanced CC     comment   delimited lingua list
#                  net      number profanity SEN       URI    whitespace
#                  zip/;

sub import {
    shift;  # Shift off the class.
    tie %RE, __PACKAGE__;
    {
        no strict 'refs';
        *{caller() . "::RE"} = \%RE;
    }

    my $saw_import;
    my $no_defaults;
    my %exclude;
    foreach my $entry (grep {!/^RE_/} @_) {
        if ($entry eq 'pattern') {
            no strict 'refs';
            *{caller() . "::pattern"} = \&pattern;
            next;
        }
        # This used to prevent $; from being set. We still recognize it,
        # but we won't do anything.
        if ($entry eq 'clean') {
            next;
        }
        if ($entry eq 'no_defaults') {
            $no_defaults ++;
            next;
        }
        if (my $module = $imports {$entry}) {
            $saw_import ++;
            eval "require $module;";
            die $@ if $@;
            next;
        }
        if ($entry =~ /^!(.*)/ && $imports {$1}) {
            $exclude {$1} ++;
            next;
        }
        # As a last resort, try to load the argument.
        my $module = $entry =~ /^Regexp::Common/
                            ? $entry
                            : "Regexp::Common::" . $entry;
        eval "require $module;";
        die $@ if $@;
    }

    unless ($saw_import || $no_defaults) {
        foreach my $module (values %imports) {
            next if $exclude {$module};
            eval "require $module;";
            die $@ if $@;
        }
    }

    my %exported;
    foreach my $entry (grep {/^RE_/} @_) {
        if ($entry =~ /^RE_(\w+_)?ALL$/) {
            my $m  = defined $1 ? $1 : "";
            my $re = qr /^RE_${m}.*$/;
            while (my ($sub, $interface) = each %sub_interface) {
                next if $exported {$sub};
                next unless $sub =~ /$re/;
                {
                    no strict 'refs';
                    *{caller() . "::$sub"} = $interface;
                }
                $exported {$sub} ++;
            }
        }
        else {
            next if $exported {$entry};
            _croak "Can't export unknown subroutine &$entry"
                unless $sub_interface {$entry};
            {
                no strict 'refs';
                *{caller() . "::$entry"} = $sub_interface {$entry};
            }
            $exported {$entry} ++;
        }
    }
}

sub AUTOLOAD { _croak "Can't $AUTOLOAD" }

sub DESTROY {}

my %cache;

my $fpat = qr/^(-\w+)/;

sub _decache {
        my @args = @{tied %{$_[0]}};
        my @nonflags = grep {!/$fpat/} @args;
        my $cache = get_cache(@nonflags);
        _croak "Can't create unknown regex: \$RE{"
            . join("}{",@args) . "}"
                unless exists $cache->{__VAL__};
        _croak "Perl $] does not support the pattern "
            . "\$RE{" . join("}{",@args)
            . "}.\nYou need Perl $cache->{__VAL__}{version} or later"
                unless ($cache->{__VAL__}{version}||0) <= $];
        my %flags = ( %{$cache->{__VAL__}{default}},
                      map { /$fpat\Q$;\E(.*)/ ? ($1 => $2)
                          : /$fpat/           ? ($1 => undef)
                          :                     ()
                          } @args);
        $cache->{__VAL__}->_clone_with(\@args, \%flags);
}

use overload q{""} => \&_decache;


sub get_cache {
        my $cache = \%cache;
        foreach (@_) {
                $cache = $cache->{$_}
                      || ($cache->{$_} = {});
        }
        return $cache;
}

sub croak_version {
        my ($entry, @args) = @_;
}

sub pattern {
        my %spec = @_;
        _croak 'pattern() requires argument: name => [ @list ]'
                unless $spec{name} && ref $spec{name} eq 'ARRAY';
        _croak 'pattern() requires argument: create => $sub_ref_or_string'
                unless $spec{create};

        if (ref $spec{create} ne "CODE") {
                my $fixed_str = "$spec{create}";
                $spec{create} = sub { $fixed_str }
        }

        my @nonflags;
        my %default;
        foreach ( @{$spec{name}} ) {
                if (/$fpat=(.*)/) {
                        $default{$1} = $2;
                }
                elsif (/$fpat\s*$/) {
                        $default{$1} = undef;
                }
                else {
                        push @nonflags, $_;
                }
        }

        my $entry = get_cache(@nonflags);

        if ($entry->{__VAL__}) {
                _carp "Overriding \$RE{"
                   . join("}{",@nonflags)
                   . "}";
        }

        $entry->{__VAL__} = bless {
                                create  => $spec{create},
                                match   => $spec{match} || \&generic_match,
                                subs    => $spec{subs}  || \&generic_subs,
                                version => $spec{version},
                                default => \%default,
                            }, 'Regexp::Common::Entry';

        foreach (@nonflags) {s/\W/X/g}
        my $subname = "RE_" . join ("_", @nonflags);
        $sub_interface{$subname} = sub {
                push @_ => undef if @_ % 2;
                my %flags = @_;
                my $pat = $spec{create}->($entry->{__VAL__},
                               {%default, %flags}, \@nonflags);
                if (exists $flags{-keep}) { $pat =~ s/\Q(?k:/(/g; }
                else { $pat =~ s/\Q(?k:/(?:/g; }
                return exists $flags {-i} ? qr /(?i:$pat)/ : qr/$pat/;
        };

        return 1;
}

sub generic_match {$_ [1] =~  /$_[0]/}
sub generic_subs  {$_ [1] =~ s/$_[0]/$_[2]/}

sub matches {
        my ($self, $str) = @_;
        my $entry = $self -> _decache;
        $entry -> {match} -> ($entry, $str);
}

sub subs {
        my ($self, $str, $newstr) = @_;
        my $entry = $self -> _decache;
        $entry -> {subs} -> ($entry, $str, $newstr);
        return $str;
}


package Regexp::Common::Entry;
# use Carp;

local $^W = 1;

use overload
    q{""} => sub {
        my ($self) = @_;
        my $pat = $self->{create}->($self, $self->{flags}, $self->{args});
        if (exists $self->{flags}{-keep}) {
            $pat =~ s/\Q(?k:/(/g;
        }
        else {
            $pat =~ s/\Q(?k:/(?:/g;
        }
        if (exists $self->{flags}{-i})   { $pat = "(?i)$pat" }
        return $pat;
    };

sub _clone_with {
    my ($self, $args, $flags) = @_;
    bless { %$self, args=>$args, flags=>$flags }, ref $self;
}
# 
#    Copyright (c) 2001 - 2005, Damian Conway and Abigail. All Rights
#  Reserved. This module is free software. It may be used, redistributed
#      and/or modified under the terms of the Perl Artistic License
#            (see http://www.perl.com/perl/misc/Artistic.html)
EOCommon
# 2}}}
$Regexp_Common_Contents{'Common/comment'} = <<'EOC';   # {{{2
# $Id: comment.pm,v 2.116 2005/03/16 00:00:02 abigail Exp $

package Regexp::Common::comment;

use strict;
local $^W = 1;

use Regexp::Common qw /pattern clean no_defaults/;
use vars qw /$VERSION/;

($VERSION) = q $Revision: 2.116 $ =~ /[\d.]+/g;

my @generic = (
    {languages => [qw /ABC Forth/],
     to_eol    => ['\\\\']},   # This is for just a *single* backslash.

    {languages => [qw /Ada Alan Eiffel lua/],
     to_eol    => ['--']},

    {languages => [qw /Advisor/],
     to_eol    => ['#|//']},

    {languages => [qw /Advsys CQL Lisp LOGO M MUMPS REBOL Scheme
                       SMITH zonefile/],
     to_eol    => [';']},

    {languages => ['Algol 60'],
     from_to   => [[qw /comment ;/]]},

    {languages => [qw {ALPACA B C C-- LPC PL/I}],
     from_to   => [[qw {/* */}]]},

    {languages => [qw /awk fvwm2 Icon mutt Perl Python QML R Ruby shell Tcl/],
     to_eol    => ['#']},

    {languages => [[BASIC => 'mvEnterprise']],
     to_eol    => ['[*!]|REM']},

    {languages => [qw /Befunge-98 Funge-98 Shelta/],
     id        => [';']},

    {languages => ['beta-Juliet', 'Crystal Report', 'Portia'],
     to_eol    => ['//']},

    {languages => ['BML'],
     from_to   => [['<?_c', '_c?>']],
    },

    {languages => [qw /C++/, 'C#', qw /Cg ECMAScript FPL Java JavaScript/],
     to_eol    => ['//'],
     from_to   => [[qw {/* */}]]},

    {languages => [qw /CLU LaTeX slrn TeX/],
     to_eol    => ['%']},

    {languages => [qw /False/],
     from_to   => [[qw !{ }!]]},

    {languages => [qw /Fortran/],
     to_eol    => ['!']},

    {languages => [qw /Haifu/],
     id        => [',']},

    {languages => [qw /ILLGOL/],
     to_eol    => ['NB']},

    {languages => [qw /INTERCAL/],
     to_eol    => [q{(?:(?:PLEASE(?:\s+DO)?|DO)\s+)?(?:NOT|N'T)}]},

    {languages => [qw /J/],
     to_eol    => ['NB[.]']},

    {languages => [qw /Nickle/],
     to_eol    => ['#'],
     from_to   => [[qw {/* */}]]},

    {languages => [qw /Oberon/],
     from_to   => [[qw /(* *)/]]},
     
    {languages => [[qw /Pascal Delphi/], [qw /Pascal Free/], [qw /Pascal GPC/]],
     to_eol    => ['//'],
     from_to   => [[qw !{ }!], [qw !(* *)!]]},

    {languages => [[qw /Pascal Workshop/]],
     id        => [qw /"/],
     from_to   => [[qw !{ }!], [qw !(* *)!], [qw !/* */!]]},

    {languages => [qw /PEARL/],
     to_eol    => ['!'],
     from_to   => [[qw {/* */}]]},

    {languages => [qw /PHP/],
     to_eol    => ['#', '//'],
     from_to   => [[qw {/* */}]]},

    {languages => [qw !PL/B!],
     to_eol    => ['[.;]']},

    {languages => [qw !PL/SQL!],
     to_eol    => ['--'],
     from_to   => [[qw {/* */}]]},

    {languages => [qw /Q-BAL/],
     to_eol    => ['`']},

    {languages => [qw /Smalltalk/],
     id        => ['"']},

    {languages => [qw /SQL/],
     to_eol    => ['-{2,}']},

    {languages => [qw /troff/],
     to_eol    => ['\\\"']},

    {languages => [qw /vi/],
     to_eol    => ['"']},

    {languages => [qw /*W/],
     from_to   => [[qw {|| !!}]]},
);

my @plain_or_nested = (
   [Caml         =>  undef,       "(*"  => "*)"],
   [Dylan        =>  "//",        "/*"  => "*/"],
   [Haskell      =>  "-{2,}",     "{-"  => "-}"],
   [Hugo         =>  "!(?!\\\\)", "!\\" => "\\!"],
   [SLIDE        =>  "#",         "(*"  => "*)"],
);

#
# Helper subs.
#

sub combine      {
    local $_ = join "|", @_;
    if (@_ > 1) {
        s/\(\?k:/(?:/g;
        $_ = "(?k:$_)";
    }
    $_
}

sub to_eol  ($)  {"(?k:(?k:$_[0])(?k:[^\\n]*)(?k:\\n))"}
sub id      ($)  {"(?k:(?k:$_[0])(?k:[^$_[0]]*)(?k:$_[0]))"}  # One char only!
sub from_to      {
    local $^W = 1;
    my ($begin, $end) = @_;

    my $qb  = quotemeta $begin;
    my $qe  = quotemeta $end;
    my $fe  = quotemeta substr $end   => 0, 1;
    my $te  = quotemeta substr $end   => 1;

    "(?k:(?k:$qb)(?k:(?:[^$fe]+|$fe(?!$te))*)(?k:$qe))";
}


my $count = 0;
sub nested {
    local $^W = 1;
    my ($begin, $end) = @_;

    $count ++;
    my $r = '(??{$Regexp::Common::comment ['. $count . ']})';

    my $qb  = quotemeta $begin;
    my $qe  = quotemeta $end;
    my $fb  = quotemeta substr $begin => 0, 1;
    my $fe  = quotemeta substr $end   => 0, 1;

    my $tb  = quotemeta substr $begin => 1;
    my $te  = quotemeta substr $end   => 1;

    use re 'eval';

    my $re;
    if ($fb eq $fe) {
        $re = qr /(?:$qb(?:(?>[^$fb]+)|$fb(?!$tb)(?!$te)|$r)*$qe)/;
    }
    else {
        local $"      =  "|";
        my   @clauses =  "(?>[^$fb$fe]+)";
        push @clauses => "$fb(?!$tb)" if length $tb;
        push @clauses => "$fe(?!$te)" if length $te;
        push @clauses =>  $r;
        $re           =   qr /(?:$qb(?:@clauses)*$qe)/;
    }

    $Regexp::Common::comment [$count] = qr/$re/;
}

#
# Process data.
#

foreach my $info (@plain_or_nested) {
    my ($language, $mark, $begin, $end) = @$info;
    pattern name    => [comment => $language],
            create  =>
                sub {my $re     = nested $begin => $end;
                     my $prefix = defined $mark ? $mark . "[^\n]*\n|" : "";
                     exists $_ [1] -> {-keep} ? qr /($prefix$re)/
                                              : qr  /$prefix$re/
                },
            version => 5.006,
            ;
}


foreach my $group (@generic) {
    my $pattern = combine +(map {to_eol   $_} @{$group -> {to_eol}}),
                           (map {from_to @$_} @{$group -> {from_to}}),
                           (map {id       $_} @{$group -> {id}}),
                  ;
    foreach my $language  (@{$group -> {languages}}) {
        pattern name    => [comment => ref $language ? @$language : $language],
                create  => $pattern,
                ;
    }
}
                

    
#
# Other languages.
#

# http://www.pascal-central.com/docs/iso10206.txt
pattern name    => [qw /comment Pascal/],
        create  => '(?k:' . '(?k:[{]|[(][*])'
                          . '(?k:[^}*]*(?:[*][^)][^}*]*)*)'
                          . '(?k:[}]|[*][)])'
                          . ')'
        ;

# http://www.templetons.com/brad/alice/language/
pattern name    =>  [qw /comment Pascal Alice/],
        create  =>  '(?k:(?k:[{])(?k:[^}\n]*)(?k:[}]))'
        ;


# http://westein.arb-phys.uni-dortmund.de/~wb/a68s.txt
pattern name    => [qw (comment), 'Algol 68'],
        create  => q {(?k:(?:#[^#]*#)|}                           .
                   q {(?:\bco\b(?:[^c]+|\Bc|\bc(?!o\b))*\bco\b)|} .
                   q {(?:\bcomment\b(?:[^c]+|\Bc|\bc(?!omment\b))*\bcomment\b))}
        ;


# See rules 91 and 92 of ISO 8879 (SGML).
# Charles F. Goldfarb: "The SGML Handbook".
# Oxford: Oxford University Press. 1990. ISBN 0-19-853737-9.
# Ch. 10.3, pp 390.
pattern name    => [qw (comment HTML)],
        create  => q {(?k:(?k:<!)(?k:(?:--(?k:[^-]*(?:-[^-]+)*)--\s*)*)(?k:>))},
        ;


pattern name    => [qw /comment SQL MySQL/],
        create  => q {(?k:(?:#|-- )[^\n]*\n|} .
                   q {/\*(?:(?>[^*;"']+)|"[^"]*"|'[^']*'|\*(?!/))*(?:;|\*/))},
        ;

# Anything that isn't <>[]+-.,
# http://home.wxs.nl/~faase009/Ha_BF.html
pattern name    => [qw /comment Brainfuck/],
        create  => '(?k:[^<>\[\]+\-.,]+)'
        ;

# Squeak is a variant of Smalltalk-80.
# http://www.squeak.
# http://mucow.com/squeak-qref.html
pattern name    => [qw /comment Squeak/],
        create  => '(?k:(?k:")(?k:[^"]*(?:""[^"]*)*)(?k:"))'
        ;

#
# Scores of less than 5 or above 17....
# http://www.cliff.biffle.org/esoterica/beatnik.html
@Regexp::Common::comment::scores = (1,  3,  3,  2,  1,  4,  2,  4,  1,  8,
                                    5,  1,  3,  1,  1,  3, 10,  1,  1,  1,
                                    1,  4,  4,  8,  4, 10);
pattern name    =>  [qw /comment Beatnik/],
        create  =>  sub {
            use re 'eval';
            my ($s, $x);
            my $re = qr {\b([A-Za-z]+)\b
                         (?(?{($s, $x) = (0, lc $^N);
                              $s += $Regexp::Common::comment::scores
                                    [ord (chop $x) - ord ('a')] while length $x;
                              $s  >= 5 && $s < 18})XXX|)}x;
            $re;
        },
        version  => 5.008,
        ;


# http://www.cray.com/craydoc/manuals/007-3692-005/html-007-3692-005/
#  (Goto table of contents/3.3 Source Form)
# Fortran, in fixed format. Comments start with a C, c or * in the first
# column, or a ! anywhere, but the sixth column. Then end with a newline.
pattern name    =>  [qw /comment Fortran fixed/],
        create  =>  '(?k:(?k:(?:^[Cc*]|(?<!^.....)!))(?k:[^\n]*)(?k:\n))'
        ;


# http://www.csis.ul.ie/cobol/Course/COBOLIntro.htm
# Traditionally, comments in COBOL were indicated with an asterisk in
# the seventh column. Modern compilers may be more lenient.
pattern name    =>  [qw /comment COBOL/],
        create  =>  '(?<=^......)(?k:(?k:[*])(?k:[^\n]*)(?k:\n))',
        version =>  '5.008',
        ;

1;
#
#    Copyright (c) 2001 - 2003, Damian Conway. All Rights Reserved.
#      This module is free software. It may be used, redistributed
#     and/or modified under the terms of the Perl Artistic License
#           (see http://www.perl.com/perl/misc/Artistic.html)
EOC
# 2}}}
$Regexp_Common_Contents{'Common/balanced'} = <<'EOB';   # {{{2
package Regexp::Common::balanced; {

use strict;
local $^W = 1;

use vars qw /$VERSION/;
($VERSION) = q $Revision: 2.101 $ =~ /[\d.]+/g;

use Regexp::Common qw /pattern clean no_defaults/;

my %closer = ( '{'=>'}', '('=>')', '['=>']', '<'=>'>' );
my $count = -1;
my %cache;

sub nested {
    local $^W = 1;
    my ($start, $finish) = @_;

    return $Regexp::Common::balanced [$cache {$start} {$finish}]
            if exists $cache {$start} {$finish};

    $count ++;
    my $r = '(??{$Regexp::Common::balanced ['. $count . ']})';

    my @starts   = map {s/\\(.)/$1/g; $_} grep {length}
                        $start  =~ /([^|\\]+|\\.)+/gs;
    my @finishes = map {s/\\(.)/$1/g; $_} grep {length}
                        $finish =~ /([^|\\]+|\\.)+/gs;

    push @finishes => ($finishes [-1]) x (@starts - @finishes);

    my @re;
    local $" = "|";
    foreach my $begin (@starts) {
        my $end = shift @finishes;

        my $qb  = quotemeta $begin;
        my $qe  = quotemeta $end;
        my $fb  = quotemeta substr $begin => 0, 1;
        my $fe  = quotemeta substr $end   => 0, 1;

        my $tb  = quotemeta substr $begin => 1;
        my $te  = quotemeta substr $end   => 1;

        use re 'eval';

        my $add;
        if ($fb eq $fe) {
            push @re =>
                   qr /(?:$qb(?:(?>[^$fb]+)|$fb(?!$tb)(?!$te)|$r)*$qe)/;
        }
        else {
            my   @clauses =  "(?>[^$fb$fe]+)";
            push @clauses => "$fb(?!$tb)" if length $tb;
            push @clauses => "$fe(?!$te)" if length $te;
            push @clauses =>  $r;
            push @re      =>  qr /(?:$qb(?:@clauses)*$qe)/;
        }
    }

    $cache {$start} {$finish} = $count;
    $Regexp::Common::balanced [$count] = qr/@re/;
}


pattern name    => [qw /balanced -parens=() -begin= -end=/],
        create  => sub {
            my $flag = $_[1];
            unless (defined $flag -> {-begin} && length $flag -> {-begin} &&
                    defined $flag -> {-end}   && length $flag -> {-end}) {
                my @open  = grep {index ($flag->{-parens}, $_) >= 0}
                             ('[','(','{','<');
                my @close = map {$closer {$_}} @open;
                $flag -> {-begin} = join "|" => @open;
                $flag -> {-end}   = join "|" => @close;
            }
            my $pat = nested @$flag {qw /-begin -end/};
            return exists $flag -> {-keep} ? qr /($pat)/ : $pat;
        },
        version => 5.006,
        ;

}

1;
#
#     Copyright (c) 2001 - 2003, Damian Conway. All Rights Reserved.
#       This module is free software. It may be used, redistributed
#      and/or modified under the terms of the Perl Artistic License
#            (see http://www.perl.com/perl/misc/Artistic.html)
EOB
# 2}}}
$Regexp_Common_Contents{'Common/delimited'} = <<'EOD';   # {{{2
# $Id: delimited.pm,v 2.104 2005/03/16 00:22:45 abigail Exp $

package Regexp::Common::delimited;

use strict;
local $^W = 1;

use Regexp::Common qw /pattern clean no_defaults/;
use vars qw /$VERSION/;

($VERSION) = q $Revision: 2.104 $ =~ /[\d.]+/g;

sub gen_delimited {

    my ($dels, $escs) = @_;
    # return '(?:\S*)' unless $dels =~ /\S/;
    if (length $escs) {
        $escs .= substr ($escs, -1) x (length ($dels) - length ($escs));
    }
    my @pat = ();
    my $i;
    for ($i=0; $i < length $dels; $i++) {
        my $del = quotemeta substr ($dels, $i, 1);
        my $esc = length($escs) ? quotemeta substr ($escs, $i, 1) : "";
        if ($del eq $esc) {
            push @pat,
                 "(?k:$del)(?k:[^$del]*(?:(?:$del$del)[^$del]*)*)(?k:$del)";
        }
        elsif (length $esc) {
            push @pat,
                 "(?k:$del)(?k:[^$esc$del]*(?:$esc.[^$esc$del]*)*)(?k:$del)";
        }
        else {
            push @pat, "(?k:$del)(?k:[^$del]*)(?k:$del)";
        }
    }
    my $pat = join '|', @pat;
    return "(?k:$pat)";
}

sub _croak {
    require Carp;
    goto &Carp::croak;
}

pattern name   => [qw( delimited -delim= -esc=\\ )],
        create => sub {my $flags = $_[1];
                       _croak 'Must specify delimiter in $RE{delimited}'
                             unless length $flags->{-delim};
                       return gen_delimited (@{$flags}{-delim, -esc});
                  },
        ;

pattern name   => [qw( quoted -esc=\\ )],
        create => sub {my $flags = $_[1];
                       return gen_delimited (q{"'`}, $flags -> {-esc});
                  },
        ;


1;
#
#     Copyright (c) 2001 - 2003, Damian Conway. All Rights Reserved.
#       This module is free software. It may be used, redistributed
#      and/or modified under the terms of the Perl Artistic License
#            (see http://www.perl.com/perl/misc/Artistic.html)
EOD
# 2}}}
    my $problems        = 0;
    $HAVE_Rexexp_Common = 0;
    my $dir             = "";
    if ($opt_sdir) {
        # write to the user-defined scratch directory
        $dir = $opt_sdir;
    } else {
        # let File::Temp create a suitable temporary directory
        $dir = tempdir( CLEANUP => 1 );  # 1 = delete on exit
    }
    print "Using temp dir [$dir] to install Regexp::Common\n" if $opt_v;
    my $Regexp_dir        = "$dir/Regexp";
    my $Regexp_Common_dir = "$dir/Regexp/Common";
    mkdir $Regexp_dir       ;
    mkdir $Regexp_Common_dir;

    foreach my $module_file (keys %Regexp_Common_Contents) {
        my $OUT = new IO::File "$dir/Regexp/${module_file}.pm", "w";
        if (defined $OUT) {
            print $OUT $Regexp_Common_Contents{$module_file};
            $OUT->close;
        } else {
            warn "Failed to install Regexp::${module_file}.pm\n";
            $problems = 1;
        }
    }

    push @INC, $dir;
    eval "use Regexp::Common qw /comment RE_comment_HTML balanced/";
    $HAVE_Rexexp_Common = 1 unless $problems;
} # 1}}}
sub Install_Algorithm_Diff {                 # {{{1
    # Installs Tye McQueen's Algorithm::Diff module, v1.1902, into a 
    # temporary directory for the duration of this run.

my $Algorithm_Diff_Contents = <<'EOAlgDiff'; # {{{2
package Algorithm::Diff;
# Skip to first "=head" line for documentation.
use strict;

use integer;    # see below in _replaceNextLargerWith() for mod to make
                # if you don't use this
use vars qw( $VERSION @EXPORT_OK );
$VERSION = 1.19_02;
#          ^ ^^ ^^-- Incremented at will
#          | \+----- Incremented for non-trivial changes to features
#          \-------- Incremented for fundamental changes
require Exporter;
*import    = \&Exporter::import;
@EXPORT_OK = qw(
    prepare LCS LCSidx LCS_length
    diff sdiff compact_diff
    traverse_sequences traverse_balanced
);

# McIlroy-Hunt diff algorithm
# Adapted from the Smalltalk code of Mario I. Wolczko, <mario@wolczko.com>
# by Ned Konz, perl@bike-nomad.com
# Updates by Tye McQueen, http://perlmonks.org/?node=tye

# Create a hash that maps each element of $aCollection to the set of
# positions it occupies in $aCollection, restricted to the elements
# within the range of indexes specified by $start and $end.
# The fourth parameter is a subroutine reference that will be called to
# generate a string to use as a key.
# Additional parameters, if any, will be passed to this subroutine.
#
# my $hashRef = _withPositionsOfInInterval( \@array, $start, $end, $keyGen );

sub _withPositionsOfInInterval
{
    my $aCollection = shift;    # array ref
    my $start       = shift;
    my $end         = shift;
    my $keyGen      = shift;
    my %d;
    my $index;
    for ( $index = $start ; $index <= $end ; $index++ )
    {
        my $element = $aCollection->[$index];
        my $key = &$keyGen( $element, @_ );
        if ( exists( $d{$key} ) )
        {
            unshift ( @{ $d{$key} }, $index );
        }
        else
        {
            $d{$key} = [$index];
        }
    }
    return wantarray ? %d : \%d;
}

# Find the place at which aValue would normally be inserted into the
# array. If that place is already occupied by aValue, do nothing, and
# return undef. If the place does not exist (i.e., it is off the end of
# the array), add it to the end, otherwise replace the element at that
# point with aValue.  It is assumed that the array's values are numeric.
# This is where the bulk (75%) of the time is spent in this module, so
# try to make it fast!

sub _replaceNextLargerWith
{
    my ( $array, $aValue, $high ) = @_;
    $high ||= $#$array;

    # off the end?
    if ( $high == -1 || $aValue > $array->[-1] )
    {
        push ( @$array, $aValue );
        return $high + 1;
    }

    # binary search for insertion point...
    my $low = 0;
    my $index;
    my $found;
    while ( $low <= $high )
    {
        $index = ( $high + $low ) / 2;

        # $index = int(( $high + $low ) / 2);  # without 'use integer'
        $found = $array->[$index];

        if ( $aValue == $found )
        {
            return undef;
        }
        elsif ( $aValue > $found )
        {
            $low = $index + 1;
        }
        else
        {
            $high = $index - 1;
        }
    }

    # now insertion point is in $low.
    $array->[$low] = $aValue;    # overwrite next larger
    return $low;
}

# This method computes the longest common subsequence in $a and $b.

# Result is array or ref, whose contents is such that
#   $a->[ $i ] == $b->[ $result[ $i ] ]
# foreach $i in ( 0 .. $#result ) if $result[ $i ] is defined.

# An additional argument may be passed; this is a hash or key generating
# function that should return a string that uniquely identifies the given
# element.  It should be the case that if the key is the same, the elements
# will compare the same. If this parameter is undef or missing, the key
# will be the element as a string.

# By default, comparisons will use "eq" and elements will be turned into keys
# using the default stringizing operator '""'.

# Additional parameters, if any, will be passed to the key generation
# routine.

sub _longestCommonSubsequence
{
    my $a        = shift;    # array ref or hash ref
    my $b        = shift;    # array ref or hash ref
    my $counting = shift;    # scalar
    my $keyGen   = shift;    # code ref
    my $compare;             # code ref

    if ( ref($a) eq 'HASH' )
    {                        # prepared hash must be in $b
        my $tmp = $b;
        $b = $a;
        $a = $tmp;
    }

    # Check for bogus (non-ref) argument values
    if ( !ref($a) || !ref($b) )
    {
        my @callerInfo = caller(1);
        die 'error: must pass array or hash references to ' . $callerInfo[3];
    }

    # set up code refs
    # Note that these are optimized.
    if ( !defined($keyGen) )    # optimize for strings
    {
        $keyGen = sub { $_[0] };
        $compare = sub { my ( $a, $b ) = @_; $a eq $b };
    }
    else
    {
        $compare = sub {
            my $a = shift;
            my $b = shift;
            &$keyGen( $a, @_ ) eq &$keyGen( $b, @_ );
        };
    }

    my ( $aStart, $aFinish, $matchVector ) = ( 0, $#$a, [] );
    my ( $prunedCount, $bMatches ) = ( 0, {} );

    if ( ref($b) eq 'HASH' )    # was $bMatches prepared for us?
    {
        $bMatches = $b;
    }
    else
    {
        my ( $bStart, $bFinish ) = ( 0, $#$b );

        # First we prune off any common elements at the beginning
        while ( $aStart <= $aFinish
            and $bStart <= $bFinish
            and &$compare( $a->[$aStart], $b->[$bStart], @_ ) )
        {
            $matchVector->[ $aStart++ ] = $bStart++;
            $prunedCount++;
        }

        # now the end
        while ( $aStart <= $aFinish
            and $bStart <= $bFinish
            and &$compare( $a->[$aFinish], $b->[$bFinish], @_ ) )
        {
            $matchVector->[ $aFinish-- ] = $bFinish--;
            $prunedCount++;
        }

        # Now compute the equivalence classes of positions of elements
        $bMatches =
          _withPositionsOfInInterval( $b, $bStart, $bFinish, $keyGen, @_ );
    }
    my $thresh = [];
    my $links  = [];

    my ( $i, $ai, $j, $k );
    for ( $i = $aStart ; $i <= $aFinish ; $i++ )
    {
        $ai = &$keyGen( $a->[$i], @_ );
        if ( exists( $bMatches->{$ai} ) )
        {
            $k = 0;
            for $j ( @{ $bMatches->{$ai} } )
            {

                # optimization: most of the time this will be true
                if ( $k and $thresh->[$k] > $j and $thresh->[ $k - 1 ] < $j )
                {
                    $thresh->[$k] = $j;
                }
                else
                {
                    $k = _replaceNextLargerWith( $thresh, $j, $k );
                }

                # oddly, it's faster to always test this (CPU cache?).
                if ( defined($k) )
                {
                    $links->[$k] =
                      [ ( $k ? $links->[ $k - 1 ] : undef ), $i, $j ];
                }
            }
        }
    }

    if (@$thresh)
    {
        return $prunedCount + @$thresh if $counting;
        for ( my $link = $links->[$#$thresh] ; $link ; $link = $link->[0] )
        {
            $matchVector->[ $link->[1] ] = $link->[2];
        }
    }
    elsif ($counting)
    {
        return $prunedCount;
    }

    return wantarray ? @$matchVector : $matchVector;
}

sub traverse_sequences
{
    my $a                 = shift;          # array ref
    my $b                 = shift;          # array ref
    my $callbacks         = shift || {};
    my $keyGen            = shift;
    my $matchCallback     = $callbacks->{'MATCH'} || sub { };
    my $discardACallback  = $callbacks->{'DISCARD_A'} || sub { };
    my $finishedACallback = $callbacks->{'A_FINISHED'};
    my $discardBCallback  = $callbacks->{'DISCARD_B'} || sub { };
    my $finishedBCallback = $callbacks->{'B_FINISHED'};
    my $matchVector = _longestCommonSubsequence( $a, $b, 0, $keyGen, @_ );

    # Process all the lines in @$matchVector
    my $lastA = $#$a;
    my $lastB = $#$b;
    my $bi    = 0;
    my $ai;

    for ( $ai = 0 ; $ai <= $#$matchVector ; $ai++ )
    {
        my $bLine = $matchVector->[$ai];
        if ( defined($bLine) )    # matched
        {
            &$discardBCallback( $ai, $bi++, @_ ) while $bi < $bLine;
            &$matchCallback( $ai,    $bi++, @_ );
        }
        else
        {
            &$discardACallback( $ai, $bi, @_ );
        }
    }

    # The last entry (if any) processed was a match.
    # $ai and $bi point just past the last matching lines in their sequences.

    while ( $ai <= $lastA or $bi <= $lastB )
    {

        # last A?
        if ( $ai == $lastA + 1 and $bi <= $lastB )
        {
            if ( defined($finishedACallback) )
            {
                &$finishedACallback( $lastA, @_ );
                $finishedACallback = undef;
            }
            else
            {
                &$discardBCallback( $ai, $bi++, @_ ) while $bi <= $lastB;
            }
        }

        # last B?
        if ( $bi == $lastB + 1 and $ai <= $lastA )
        {
            if ( defined($finishedBCallback) )
            {
                &$finishedBCallback( $lastB, @_ );
                $finishedBCallback = undef;
            }
            else
            {
                &$discardACallback( $ai++, $bi, @_ ) while $ai <= $lastA;
            }
        }

        &$discardACallback( $ai++, $bi, @_ ) if $ai <= $lastA;
        &$discardBCallback( $ai, $bi++, @_ ) if $bi <= $lastB;
    }

    return 1;
}

sub traverse_balanced
{
    my $a                 = shift;              # array ref
    my $b                 = shift;              # array ref
    my $callbacks         = shift || {};
    my $keyGen            = shift;
    my $matchCallback     = $callbacks->{'MATCH'} || sub { };
    my $discardACallback  = $callbacks->{'DISCARD_A'} || sub { };
    my $discardBCallback  = $callbacks->{'DISCARD_B'} || sub { };
    my $changeCallback    = $callbacks->{'CHANGE'};
    my $matchVector = _longestCommonSubsequence( $a, $b, 0, $keyGen, @_ );

    # Process all the lines in match vector
    my $lastA = $#$a;
    my $lastB = $#$b;
    my $bi    = 0;
    my $ai    = 0;
    my $ma    = -1;
    my $mb;

    while (1)
    {

        # Find next match indices $ma and $mb
        do {
            $ma++;
        } while(
                $ma <= $#$matchVector
            &&  !defined $matchVector->[$ma]
        );

        last if $ma > $#$matchVector;    # end of matchVector?
        $mb = $matchVector->[$ma];

        # Proceed with discard a/b or change events until
        # next match
        while ( $ai < $ma || $bi < $mb )
        {

            if ( $ai < $ma && $bi < $mb )
            {

                # Change
                if ( defined $changeCallback )
                {
                    &$changeCallback( $ai++, $bi++, @_ );
                }
                else
                {
                    &$discardACallback( $ai++, $bi, @_ );
                    &$discardBCallback( $ai, $bi++, @_ );
                }
            }
            elsif ( $ai < $ma )
            {
                &$discardACallback( $ai++, $bi, @_ );
            }
            else
            {

                # $bi < $mb
                &$discardBCallback( $ai, $bi++, @_ );
            }
        }

        # Match
        &$matchCallback( $ai++, $bi++, @_ );
    }

    while ( $ai <= $lastA || $bi <= $lastB )
    {
        if ( $ai <= $lastA && $bi <= $lastB )
        {

            # Change
            if ( defined $changeCallback )
            {
                &$changeCallback( $ai++, $bi++, @_ );
            }
            else
            {
                &$discardACallback( $ai++, $bi, @_ );
                &$discardBCallback( $ai, $bi++, @_ );
            }
        }
        elsif ( $ai <= $lastA )
        {
            &$discardACallback( $ai++, $bi, @_ );
        }
        else
        {

            # $bi <= $lastB
            &$discardBCallback( $ai, $bi++, @_ );
        }
    }

    return 1;
}

sub prepare
{
    my $a       = shift;    # array ref
    my $keyGen  = shift;    # code ref

    # set up code ref
    $keyGen = sub { $_[0] } unless defined($keyGen);

    return scalar _withPositionsOfInInterval( $a, 0, $#$a, $keyGen, @_ );
}

sub LCS
{
    my $a = shift;                  # array ref
    my $b = shift;                  # array ref or hash ref
    my $matchVector = _longestCommonSubsequence( $a, $b, 0, @_ );
    my @retval;
    my $i;
    for ( $i = 0 ; $i <= $#$matchVector ; $i++ )
    {
        if ( defined( $matchVector->[$i] ) )
        {
            push ( @retval, $a->[$i] );
        }
    }
    return wantarray ? @retval : \@retval;
}

sub LCS_length
{
    my $a = shift;                          # array ref
    my $b = shift;                          # array ref or hash ref
    return _longestCommonSubsequence( $a, $b, 1, @_ );
}

sub LCSidx
{
    my $a= shift @_;
    my $b= shift @_;
    my $match= _longestCommonSubsequence( $a, $b, 0, @_ );
    my @am= grep defined $match->[$_], 0..$#$match;
    my @bm= @{$match}[@am];
    return \@am, \@bm;
}

sub compact_diff
{
    my $a= shift @_;
    my $b= shift @_;
    my( $am, $bm )= LCSidx( $a, $b, @_ );
    my @cdiff;
    my( $ai, $bi )= ( 0, 0 );
    push @cdiff, $ai, $bi;
    while( 1 ) {
        while(  @$am  &&  $ai == $am->[0]  &&  $bi == $bm->[0]  ) {
            shift @$am;
            shift @$bm;
            ++$ai, ++$bi;
        }
        push @cdiff, $ai, $bi;
        last   if  ! @$am;
        $ai = $am->[0];
        $bi = $bm->[0];
        push @cdiff, $ai, $bi;
    }
    push @cdiff, 0+@$a, 0+@$b
        if  $ai < @$a || $bi < @$b;
    return wantarray ? @cdiff : \@cdiff;
}

sub diff
{
    my $a      = shift;    # array ref
    my $b      = shift;    # array ref
    my $retval = [];
    my $hunk   = [];
    my $discard = sub {
        push @$hunk, [ '-', $_[0], $a->[ $_[0] ] ];
    };
    my $add = sub {
        push @$hunk, [ '+', $_[1], $b->[ $_[1] ] ];
    };
    my $match = sub {
        push @$retval, $hunk
            if 0 < @$hunk;
        $hunk = []
    };
    traverse_sequences( $a, $b,
        { MATCH => $match, DISCARD_A => $discard, DISCARD_B => $add }, @_ );
    &$match();
    return wantarray ? @$retval : $retval;
}

sub sdiff
{
    my $a      = shift;    # array ref
    my $b      = shift;    # array ref
    my $retval = [];
    my $discard = sub { push ( @$retval, [ '-', $a->[ $_[0] ], "" ] ) };
    my $add = sub { push ( @$retval, [ '+', "", $b->[ $_[1] ] ] ) };
    my $change = sub {
        push ( @$retval, [ 'c', $a->[ $_[0] ], $b->[ $_[1] ] ] );
    };
    my $match = sub {
        push ( @$retval, [ 'u', $a->[ $_[0] ], $b->[ $_[1] ] ] );
    };
    traverse_balanced(
        $a,
        $b,
        {
            MATCH     => $match,
            DISCARD_A => $discard,
            DISCARD_B => $add,
            CHANGE    => $change,
        },
        @_
    );
    return wantarray ? @$retval : $retval;
}

########################################
my $Root= __PACKAGE__;
package Algorithm::Diff::_impl;
use strict;

sub _Idx()  { 0 } # $me->[_Idx]: Ref to array of hunk indices
            # 1   # $me->[1]: Ref to first sequence
            # 2   # $me->[2]: Ref to second sequence
sub _End()  { 3 } # $me->[_End]: Diff between forward and reverse pos
sub _Same() { 4 } # $me->[_Same]: 1 if pos 1 contains unchanged items
sub _Base() { 5 } # $me->[_Base]: Added to range's min and max
sub _Pos()  { 6 } # $me->[_Pos]: Which hunk is currently selected
sub _Off()  { 7 } # $me->[_Off]: Offset into _Idx for current position
sub _Min() { -2 } # Added to _Off to get min instead of max+1

sub Die
{
    require Carp;
    Carp::confess( @_ );
}

sub _ChkPos
{
    my( $me )= @_;
    return   if  $me->[_Pos];
    my $meth= ( caller(1) )[3];
    Die( "Called $meth on 'reset' object" );
}

sub _ChkSeq
{
    my( $me, $seq )= @_;
    return $seq + $me->[_Off]
        if  1 == $seq  ||  2 == $seq;
    my $meth= ( caller(1) )[3];
    Die( "$meth: Invalid sequence number ($seq); must be 1 or 2" );
}

sub getObjPkg
{
    my( $us )= @_;
    return ref $us   if  ref $us;
    return $us . "::_obj";
}

sub new
{
    my( $us, $seq1, $seq2, $opts ) = @_;
    my @args;
    for( $opts->{keyGen} ) {
        push @args, $_   if  $_;
    }
    for( $opts->{keyGenArgs} ) {
        push @args, @$_   if  $_;
    }
    my $cdif= Algorithm::Diff::compact_diff( $seq1, $seq2, @args );
    my $same= 1;
    if(  0 == $cdif->[2]  &&  0 == $cdif->[3]  ) {
        $same= 0;
        splice @$cdif, 0, 2;
    }
    my @obj= ( $cdif, $seq1, $seq2 );
    $obj[_End] = (1+@$cdif)/2;
    $obj[_Same] = $same;
    $obj[_Base] = 0;
    my $me = bless \@obj, $us->getObjPkg();
    $me->Reset( 0 );
    return $me;
}

sub Reset
{
    my( $me, $pos )= @_;
    $pos= int( $pos || 0 );
    $pos += $me->[_End]
        if  $pos < 0;
    $pos= 0
        if  $pos < 0  ||  $me->[_End] <= $pos;
    $me->[_Pos]= $pos || !1;
    $me->[_Off]= 2*$pos - 1;
    return $me;
}

sub Base
{
    my( $me, $base )= @_;
    my $oldBase= $me->[_Base];
    $me->[_Base]= 0+$base   if  defined $base;
    return $oldBase;
}

sub Copy
{
    my( $me, $pos, $base )= @_;
    my @obj= @$me;
    my $you= bless \@obj, ref($me);
    $you->Reset( $pos )   if  defined $pos;
    $you->Base( $base );
    return $you;
}

sub Next {
    my( $me, $steps )= @_;
    $steps= 1   if  ! defined $steps;
    if( $steps ) {
        my $pos= $me->[_Pos];
        my $new= $pos + $steps;
        $new= 0   if  $pos  &&  $new < 0;
        $me->Reset( $new )
    }
    return $me->[_Pos];
}

sub Prev {
    my( $me, $steps )= @_;
    $steps= 1   if  ! defined $steps;
    my $pos= $me->Next(-$steps);
    $pos -= $me->[_End]   if  $pos;
    return $pos;
}

sub Diff {
    my( $me )= @_;
    $me->_ChkPos();
    return 0   if  $me->[_Same] == ( 1 & $me->[_Pos] );
    my $ret= 0;
    my $off= $me->[_Off];
    for my $seq ( 1, 2 ) {
        $ret |= $seq
            if  $me->[_Idx][ $off + $seq + _Min ]
            <   $me->[_Idx][ $off + $seq ];
    }
    return $ret;
}

sub Min {
    my( $me, $seq, $base )= @_;
    $me->_ChkPos();
    my $off= $me->_ChkSeq($seq);
    $base= $me->[_Base] if !defined $base;
    return $base + $me->[_Idx][ $off + _Min ];
}

sub Max {
    my( $me, $seq, $base )= @_;
    $me->_ChkPos();
    my $off= $me->_ChkSeq($seq);
    $base= $me->[_Base] if !defined $base;
    return $base + $me->[_Idx][ $off ] -1;
}

sub Range {
    my( $me, $seq, $base )= @_;
    $me->_ChkPos();
    my $off = $me->_ChkSeq($seq);
    if( !wantarray ) {
        return  $me->[_Idx][ $off ]
            -   $me->[_Idx][ $off + _Min ];
    }
    $base= $me->[_Base] if !defined $base;
    return  ( $base + $me->[_Idx][ $off + _Min ] )
        ..  ( $base + $me->[_Idx][ $off ] - 1 );
}

sub Items {
    my( $me, $seq )= @_;
    $me->_ChkPos();
    my $off = $me->_ChkSeq($seq);
    if( !wantarray ) {
        return  $me->[_Idx][ $off ]
            -   $me->[_Idx][ $off + _Min ];
    }
    return
        @{$me->[$seq]}[
                $me->[_Idx][ $off + _Min ]
            ..  ( $me->[_Idx][ $off ] - 1 )
        ];
}

sub Same {
    my( $me )= @_;
    $me->_ChkPos();
    return wantarray ? () : 0
        if  $me->[_Same] != ( 1 & $me->[_Pos] );
    return $me->Items(1);
}

my %getName;
BEGIN {
    %getName= (
        same => \&Same,
        diff => \&Diff,
        base => \&Base,
        min  => \&Min,
        max  => \&Max,
        range=> \&Range,
        items=> \&Items, # same thing
    );
}

sub Get
{
    my $me= shift @_;
    $me->_ChkPos();
    my @value;
    for my $arg (  @_  ) {
        for my $word (  split ' ', $arg  ) {
            my $meth;
            if(     $word !~ /^(-?\d+)?([a-zA-Z]+)([12])?$/
                ||  not  $meth= $getName{ lc $2 }
            ) {
                Die( $Root, ", Get: Invalid request ($word)" );
            }
            my( $base, $name, $seq )= ( $1, $2, $3 );
            push @value, scalar(
                4 == length($name)
                    ? $meth->( $me )
                    : $meth->( $me, $seq, $base )
            );
        }
    }
    if(  wantarray  ) {
        return @value;
    } elsif(  1 == @value  ) {
        return $value[0];
    }
    Die( 0+@value, " values requested from ",
        $Root, "'s Get in scalar context" );
}


my $Obj= getObjPkg($Root);
no strict 'refs';

for my $meth (  qw( new getObjPkg )  ) {
    *{$Root."::".$meth} = \&{$meth};
    *{$Obj ."::".$meth} = \&{$meth};
}
for my $meth (  qw(
    Next Prev Reset Copy Base Diff
    Same Items Range Min Max Get
    _ChkPos _ChkSeq
)  ) {
    *{$Obj."::".$meth} = \&{$meth};
}

1;
# This version released by Tye McQueen (http://perlmonks.org/?node=tye).
# 
# =head1 LICENSE
# 
# Parts Copyright (c) 2000-2004 Ned Konz.  All rights reserved.
# Parts by Tye McQueen.
# 
# This program is free software; you can redistribute it and/or modify it
# under the same terms as Perl.
# 
# =head1 MAILING LIST
# 
# Mark-Jason still maintains a mailing list.  To join a low-volume mailing
# list for announcements related to diff and Algorithm::Diff, send an
# empty mail message to mjd-perl-diff-request@plover.com.
# =head1 CREDITS
# 
# Versions through 0.59 (and much of this documentation) were written by:
# 
# Mark-Jason Dominus, mjd-perl-diff@plover.com
# 
# This version borrows some documentation and routine names from
# Mark-Jason's, but Diff.pm's code was completely replaced.
# 
# This code was adapted from the Smalltalk code of Mario Wolczko
# <mario@wolczko.com>, which is available at
# ftp://st.cs.uiuc.edu/pub/Smalltalk/MANCHESTER/manchester/4.0/diff.st
# 
# C<sdiff> and C<traverse_balanced> were written by Mike Schilli
# <m@perlmeister.com>.
# 
# The algorithm is that described in
# I<A Fast Algorithm for Computing Longest Common Subsequences>,
# CACM, vol.20, no.5, pp.350-353, May 1977, with a few
# minor improvements to improve the speed.
# 
# Much work was done by Ned Konz (perl@bike-nomad.com).
# 
# The OO interface and some other changes are by Tye McQueen.
# 
EOAlgDiff
# 2}}}
    my $problems        = 0;
    $HAVE_Algorith_Diff = 0;
    my $dir             = "";
    if ($opt_sdir) {
        # write to the user-defined scratch directory
        $dir = $opt_sdir;
    } else {
        # let File::Temp create a suitable temporary directory
        $dir = tempdir( CLEANUP => 1 );  # 1 = delete on exit
    }
    print "Using temp dir [$dir] to install Algorithm::Diff\n" if $opt_v;
    my $Algorithm_dir      = "$dir/Algorithm";
    my $Algorithm_Diff_dir = "$dir/Algorithm/Diff";
    mkdir $Algorithm_dir     ;
    mkdir $Algorithm_Diff_dir;

    my $OUT = new IO::File "$dir/Algorithm/Diff.pm", "w";
    if (defined $OUT) {
        print $OUT $Algorithm_Diff_Contents;
        $OUT->close;
    } else {
        warn "Failed to install Algorithm/Diff.pm\n";
        $problems = 1;
    }

    push @INC, $dir;  # between this & Regexp::Common only need to do once
    eval "use Algorithm::Diff qw / sdiff /";
    $HAVE_Algorith_Diff = 1 unless $problems;
} # 1}}}
sub call_regexp_common {                     # {{{1
    my ($ra_lines, $language ) = @_;
    print "-> call_regexp_common\n" if $opt_v > 2;

    Install_Regexp_Common() unless $HAVE_Rexexp_Common;

    my $all_lines = join("", @{$ra_lines});

    no strict 'vars';
    # otherwise get:
    #  Global symbol "%RE" requires explicit package name at cloc line xx.
    if ($all_lines =~ $RE{comment}{$language}) {
        # Suppress "Use of uninitialized value in regexp compilation" that
        # pops up when $1 is undefined--happens if there's a bug in the $RE
        # This Pascal comment will trigger it:
        #         (* This is { another } test. **)
        # Curiously, testing for "defined $1" breaks the substitution.
        no warnings; 
        # remove   comments
        $all_lines =~ s/$1//g;
    }
    # a bogus use of %RE to avoid:
    # Name "main::RE" used only once: possible typo at cloc line xx.
    print scalar keys %RE if $opt_v < -20;
#?#print "$all_lines\n";
    print "<- call_regexp_common\n" if $opt_v > 2;
    return split("\n", $all_lines);
} # 1}}}
sub plural_form {                            # {{{1
    # For getting the right plural form on some English nouns.
    my $n = shift @_;
    if ($n == 1) { return ( 1, "" ); }
    else         { return ($n, "s"); }
} # 1}}}
sub matlab_or_objective_C {                  # {{{1
    # Decide if code is MATLAB, Objective C, or MUMPS
    my ($file        , # in
        $rh_Err      , # in   hash of error codes
        $raa_errors  , # out
        $rs_language , # out
       ) = @_;

    print "-> matlab_or_objective_C\n" if $opt_v > 2;
    # matlab markers:
    #   first line starts with "function"
    #   some lines start with "%"
    #   high marks for lines that start with [
    #
    # Objective C markers:
    #   must have at least two brace characters, { }
    #   has /* ... */ style comments
    #   some lines start with @
    #   some lines start with #include
    #
    # MUMPS:
    #   has ; comment markers
    #   do not match:  \w+\s*=\s*\w
    #   lines begin with   \s*\.?\w+\s+\w
    #   high marks for lines that start with \s*K\s+ or \s*Kill\s+

    ${$rs_language} = "";
    my $IN = new IO::File $file, "r";
    if (!defined $IN) {
        push @{$raa_errors}, [$rh_Err->{'Unable to read'} , $file];
        return;
    }

    my $DEBUG              = 0;

    my $matlab_points      = 0;
    my $objective_C_points = 0;
    my $mumps_points       = 0;
    my $has_braces         = 0;
    while (<$IN>) {
        ++$has_braces if m/[{}]/;
        ++$mumps_points if $. == 1 and m{^[A-Z]};
        if      (m{^\s*/\*}) {           #   /*
            ++$objective_C_points;
            --$matlab_points;
printf ".m:  /*     obj C=% 2d  matlab=% 2d  mumps=% 2d\n", $objective_C_points, $matlab_points, $mumps_points if $DEBUG;
        } elsif (m{\w+\s*=\s*\[}) {      # matrix assignment, very matlab
            $matlab_points += 5;
printf ".m:  \\w=[   obj C=% 2d  matlab=% 2d  mumps=% 2d\n", $objective_C_points, $matlab_points, $mumps_points if $DEBUG;
        } elsif (m{^\s*\w+\s*=\s*}) {    # definitely not MUMPS
            --$mumps_points;
printf ".m:  \\w=    obj C=% 2d  matlab=% 2d  mumps=% 2d\n", $objective_C_points, $matlab_points, $mumps_points if $DEBUG;
        } elsif (m{^\s*\.?(\w)\s+(\w)} and $1 !~ /\d/ and $2 !~ /\d/) {
            ++$mumps_points;
printf ".m:  \\w \\w  obj C=% 2d  matlab=% 2d  mumps=% 2d\n", $objective_C_points, $matlab_points, $mumps_points if $DEBUG;
        } elsif (m{^\s*;}) {
            ++$mumps_points;
printf ".m:  ;      obj C=% 2d  matlab=% 2d  mumps=% 2d\n", $objective_C_points, $matlab_points, $mumps_points if $DEBUG;
        } elsif (m{^\s*#(include|import)}) {
            # Objective C without a doubt
            $objective_C_points = 1;
            $matlab_points      = 0;
printf ".m: #includ obj C=% 2d  matlab=% 2d  mumps=% 2d\n", $objective_C_points, $matlab_points, $mumps_points if $DEBUG;
            last;
        } elsif (m{^\s*@(interface|implementation|protocol|public|protected|private|end)\s}o) {
            # Objective C without a doubt
            $objective_C_points = 1;
            $matlab_points      = 0;
printf ".m: keyword obj C=% 2d  matlab=% 2d  mumps=% 2d\n", $objective_C_points, $matlab_points, $mumps_points if $DEBUG;
            last;
        } elsif (m{^\s*\[}) {             #   line starts with [  -- very matlab
            $matlab_points += 5;
printf ".m:  [      obj C=% 2d  matlab=% 2d  mumps=% 2d\n", $objective_C_points, $matlab_points, $mumps_points if $DEBUG;
        } elsif (m{^\sK(ill)?\s+}) {
            $mumps_points  += 5;
printf ".m:  Kill   obj C=% 2d  matlab=% 2d  mumps=% 2d\n", $objective_C_points, $matlab_points, $mumps_points if $DEBUG;
        } elsif (m{^\s*function}) {
            --$objective_C_points;
            ++$matlab_points;
printf ".m:  funct  obj C=% 2d  matlab=% 2d  mumps=% 2d\n", $objective_C_points, $matlab_points, $mumps_points if $DEBUG;
        } elsif (m{^\s*%}) {              #   %
            --$objective_C_points;
            ++$matlab_points;
            ++$mumps_points;
printf ".m:  pcent  obj C=% 2d  matlab=% 2d  mumps=% 2d\n", $objective_C_points, $matlab_points, $mumps_points if $DEBUG;
        }
    }
    $IN->close;

    print "<- matlab_or_objective_C(matlab=$matlab_points, C=$objective_C_points, mumps=$mumps_points)\n"
        if $opt_v > 2;
    $objective_C_points = -9.9e20 unless $has_braces >= 2;
    if      (($matlab_points > $objective_C_points) and
             ($matlab_points > $mumps_points)      ) {
        ${$rs_language} = "MATLAB";
    } elsif (($mumps_points > $objective_C_points) and
             ($mumps_points > $matlab_points)      ) {
        ${$rs_language} = "MUMPS";
    } else {
        ${$rs_language} = "Objective C";
    }

} # 1}}}
sub html_colored_text {                      # {{{1
    # http://www.pagetutor.com/pagetutor/makapage/pics/net216-2.gif
    my ($color, $text) = @_;
#?#die "html_colored_text($text)";
    if      ($color =~ /^red$/i)   {
        $color = "#ff0000";
    } elsif ($color =~ /^green$/i) {
        $color = "#00ff00";
    } elsif ($color =~ /^blue$/i)  {
        $color = "#0000ff";
    } elsif ($color =~ /^grey$/i)  {
        $color = "#cccccc";
    }
#   return "" unless $text;
    return '<font color="' . $color . '">' . html_metachars($text) . "</font>";
} # 1}}}
sub html_metachars {                         # {{{1
    # Replace HTML metacharacters with their printable forms.
    # Future:  use HTML-Encoder-0.00_04/lib/HTML/Encoder.pm
    # from Fabiano Reese Righetti's HTML::Encoder module if 
    # this subroutine proves to be too simplistic.
    my ($string, ) = shift @_;

    my  @in_chars    = split(//, $string);
    my  @out_chars   = ();
    foreach my $c (@in_chars) {
        if      ($c eq '<') {
            push @out_chars, '&lt;'
        } elsif ($c eq '>') {
            push @out_chars, '&gt;'
        } elsif ($c eq '&') {
            push @out_chars, '&amp;'
        } else {
            push @out_chars, $c;
        }
    }
    return join "", @out_chars; 
} # 1}}}
sub test_alg_diff {                          # {{{1
    my ($file_1 ,
        $file_2 )
       = @_;
    my $fh_1 = new IO::File $file_1, "r";
    die "Unable to read $file_1:  $!\n" unless defined $fh_1;
    chomp(my @lines_1 = <$fh_1>);
    $fh_1->close;

    my $fh_2 = new IO::File $file_2, "r";
    die "Unable to read $file_2:  $!\n" unless defined $fh_2;
    chomp(my @lines_2 = <$fh_2>);
    $fh_2->close;

    my $n_no_change = 0;
    my $n_modified  = 0;
    my $n_added     = 0;
    my $n_deleted   = 0;
    my @min_sdiff   = ();
my $NN = chr(27) . "[0m";  # normal
my $BB = chr(27) . "[1m";  # bold

    my @sdiffs = sdiff( \@lines_1, \@lines_2 );
    foreach my $entry (@sdiffs) {
        my ($out_1, $out_2) = ('', '');
        if ($entry->[0] eq 'u') { 
            ++$n_no_change; 
          # $out_1 = $entry->[1];
          # $out_2 = $entry->[2];
            next; 
        }
#       push @min_sdiff, $entry;
        if      ($entry->[0] eq 'c') { 
            ++$n_modified;
            ($out_1, $out_2) = diff_two_strings($entry->[1], $entry->[2]);
            $out_1 =~ s/\cA(\w)/${BB}$1${NN}/g;
            $out_2 =~ s/\cA(\w)/${BB}$1${NN}/g;
          # $out_1 =~ s/\cA//g;
          # $out_2 =~ s/\cA//g;
        } elsif ($entry->[0] eq '+') { 
            ++$n_added;
            $out_1 = $entry->[1];
            $out_2 = $entry->[2];
        } elsif ($entry->[0] eq '-') { 
            ++$n_deleted;
            $out_1 = $entry->[1];
            $out_2 = $entry->[2];
        } elsif ($entry->[0] eq 'u') { 
        } else { die "unknown entry->[0]=[$entry->[0]]\n"; }
        printf "%-80s | %s\n", $out_1, $out_2;
    }

#   foreach my $entry (@min_sdiff) {
#       printf "DIFF:  %s  %s  %s\n", @{$entry};
#   }
} # 1}}}
sub write_comments_to_html {                 # {{{1
    my ($filename      , # in
        $rah_diff_L    , # in  see routine array_diff() for explanation
        $rah_diff_R    , # in  see routine array_diff() for explanation
        $rh_blank      , # in  location and counts of blank lines
       ) = @_;

    print "-> write_comments_to_html($filename)\n" if $opt_v > 2;
    my $file = $filename . ".html";
#use Data::Dumper;
#print Dumper("rah_diff_L", $rah_diff_L, "rah_diff_R", $rah_diff_R);
    my $OUT = new IO::File $file, "w";
    if (!defined $OUT) {
        warn "Unable to write to $file\n";
        print "<- write_comments_to_html\n" if $opt_v > 2;
        return;
    }

    my $approx_line_count = scalar @{$rah_diff_L};
    my $n_digits = 1 + int(log($approx_line_count)/2.30258509299405); # log_10

    my $html_out = html_header($filename);

    my $comment_line_number = 0;
    for (my $i = 0; $i < scalar @{$rah_diff_R}; $i++) {
        if (defined $rh_blank->{$i}) {
            foreach (1..$rh_blank->{$i}) {
                $html_out .= "<!-- blank -->\n";
            }
        }
        my $line_num = "";
        my $pre      = "";
        my $post     = '</span> &nbsp;';
warn "undef rah_diff_R[$i]{type} " unless defined $rah_diff_R->[$i]{type};
        if ($rah_diff_R->[$i]{type} eq 'nonexist') {
            ++$comment_line_number;
            $line_num = sprintf "\&nbsp; <span class=\"clinenum\"> %0${n_digits}d %s",
                            $comment_line_number, $post;
            $pre = '<span class="comment">';
            $html_out .= $line_num;  
            $html_out .= $pre .  
                         html_metachars($rah_diff_L->[$i]{char}) . 
                         $post . "\n";
            next;
        }
        if      ($rah_diff_R->[$i]{type} eq 'code' and
                 $rah_diff_R->[$i]{desc} eq 'same') {
            # entire line remains as-is
            $line_num = sprintf "\&nbsp; <span class=\"linenum\"> %0${n_digits}d %s",
                            $rah_diff_R->[$i]{lnum}, $post;
            $pre    = '<span class="normal">';
            $html_out .= $line_num;  
            $html_out .= $pre . 
                         html_metachars($rah_diff_R->[$i]{char}) . $post;
#XX     } elsif ($rah_diff_R->[$i]{type} eq 'code') { # code+comments
#XX
#XX         $line_num = '<span class="linenum">' .
#XX                      $rah_diff_R->[$i]{lnum} . $post;
#XX         $html_out .= $line_num;  
#XX
#XX         my @strings = @{$rah_diff_R->[$i]{char}{strings}}; 
#XX         my @type    = @{$rah_diff_R->[$i]{char}{type}}; 
#XX         for (my $i = 0; $i < scalar @strings; $i++) {
#XX             if ($type[$i] eq 'u') {
#XX                 $pre = '<span class="normal">';
#XX             } else {
#XX                 $pre = '<span class="comment">';
#XX             }
#XX             $html_out .= $pre .  html_metachars($strings[$i]) . $post;
#XX         }
# print Dumper(@strings, @type); die;

        } elsif ($rah_diff_R->[$i]{type} eq 'comment') {
            $line_num = '<span class="clinenum">' . $comment_line_number . $post;
            # entire line is a comment
            $pre    = '<span class="comment">';
            $html_out .= $pre .
                         html_metachars($rah_diff_R->[$i]{char}) . $post;
        }
#printf "%-30s %s %-30s\n", $line_1, $separator, $line_2;
        $html_out .= "\n";
    }

    $html_out .= html_end();

    my $out_file = "$filename.html";
    open  OUT, ">$out_file" or die "Cannot write to $out_file $!\n";
    print OUT $html_out;
    close OUT;
    print "Wrote $out_file\n" unless $opt_quiet;
    $OUT->close;

    print "<- write_comments_to_html\n" if $opt_v > 2;
} # 1}}}
sub array_diff {                             # {{{1
    my ($file          , # in  only used for error reporting
        $ra_lines_L    , # in  array of lines in Left  file (no blank lines)
        $ra_lines_R    , # in  array of lines in Right file (no blank lines)
        $mode          , # in  "comment" | "revision"
        $rah_diff_L    , # out
        $rah_diff_R    , # out
        $raa_Errors    , # in/out
       ) = @_;

    # This routine operates in two ways:
    # A. Computes diffs of the same file with and without comments.
    #    This is used to classify lines as code, comments, or blank.
    # B. Computes diffs of two revisions of a file.  This method
    #    requires a prior run of method A using the older version
    #    of the file because it needs lines to be classified.

    # $rah_diff structure:
    # An array with n entries where n equals the number of lines in 
    # an sdiff of the two files.  Each entry in the array describes
    # the contents of the corresponding line in file Left and file Right:
    #  diff[]{type} = blank | code | code+comment | comment | nonexist
    #        {lnum} = line number within the original file (1-based)
    #        {desc} = same | added | removed | modified
    #        {char} = the input line unless {desc} = 'modified' in
    #                 which case
    #        {char}{strings} = [ substrings ]
    #        {char}{type}    = [ disposition (added, removed, etc)]
    #

    print "-> array_diff()\n" if $opt_v > 2;
    my $COMMENT_MODE = 0;
       $COMMENT_MODE = 1 if $mode eq "comment";

#print "array_diff(mode=$mode)\n";
#print Dumper("block left:" , $ra_lines_L);
#print Dumper("block right:", $ra_lines_R);

    my @sdiffs = sdiff($ra_lines_L, $ra_lines_R);
#use Data::Dumper::Simple;
#print Dumper($ra_lines_L, $ra_lines_R, @sdiffs);
#die;

    my $n_L        = 0;
    my $n_R        = 0;
    my $n_sdiff    = 0;  # index to $rah_diff_L, $rah_diff_R
    @{$rah_diff_L} = ();
    @{$rah_diff_R} = ();
    foreach my $triple (@sdiffs) {
        my $flag   = $triple->[0];
        my $line_L = $triple->[1];
        my $line_R = $triple->[2];
        $rah_diff_L->[$n_sdiff]{char} = $line_L;
        $rah_diff_R->[$n_sdiff]{char} = $line_R;
        if      ($flag eq 'u') {  # u = unchanged
            ++$n_L;
            ++$n_R;
            if ($COMMENT_MODE) {
                # line exists in both with & without comments, must be code
                $rah_diff_L->[$n_sdiff]{type} = "code";
                $rah_diff_R->[$n_sdiff]{type} = "code";
            }
            $rah_diff_L->[$n_sdiff]{desc} = "same";
            $rah_diff_R->[$n_sdiff]{desc} = "same";
            $rah_diff_L->[$n_sdiff]{lnum} = $n_L;
            $rah_diff_R->[$n_sdiff]{lnum} = $n_R;
        } elsif ($flag eq 'c') {  # c = changed
# warn "per line sdiff() commented out\n"; if (0) {
            ++$n_L;
            ++$n_R;

            if ($COMMENT_MODE) {
                # line has text both with & without comments;
                # count as code
                $rah_diff_L->[$n_sdiff]{type} = "code";
                $rah_diff_R->[$n_sdiff]{type} = "code";
            }

            my @chars_L = split '', $line_L;
            my @chars_R = split '', $line_R;

#XX         my @inline_sdiffs = sdiff( \@chars_L, \@chars_R );

#use Data::Dumper::Simple; 
#if ($n_R == 6 or $n_R == 1 or $n_R == 2) {
#print "L=[$line_L]\n";
#print "R=[$line_R]\n";
#print Dumper(@chars_L, @chars_R, @inline_sdiffs);
#}
#XX         my @index = ();
#XX         foreach my $il_triple (@inline_sdiffs) {
#XX             # make an array of u|c|+|- corresponding
#XX             # to each character
#XX             push @index, $il_triple->[0];
#XX         }
#XX#print Dumper(@index); die;
#XX          # expect problems if arrays @index and $inline_sdiffs[1];
#XX          # (@{$inline_sdiffs->[1]} are the characters of line_L)
#XX          # aren't the same length
#XX          my $prev_type = $index[0];
#XX          my @strings   = ();  # blocks of consecutive code or comment
#XX          my @type      = ();  # u (=code) or c (=comment)
#XX          my $j_str     = 0;
#XX          $strings[$j_str] .= $chars_L[0];
#XX          $type[$j_str] = $prev_type;
#XX          for (my $i = 1; $i < scalar @chars_L; $i++) {
#XX              if ($index[$i] ne $prev_type) {
#XX                  ++$j_str;
#XX#print "change at j_str=$j_str type=$index[$i]\n";
#XX                  $type[$j_str] = $index[$i];
#XX                  $prev_type    = $index[$i];
#XX              }
#XX              $strings[$j_str] .= $chars_L[$i];
#XX          }
# print Dumper(@strings, @type); die;
#XX         delete $rah_diff_R->[$n_sdiff]{char};
#XX         @{$rah_diff_R->[$n_sdiff]{char}{strings}} = @strings;
#XX         @{$rah_diff_R->[$n_sdiff]{char}{type}}    = @type;
            $rah_diff_L->[$n_sdiff]{desc} = "modified";
            $rah_diff_R->[$n_sdiff]{desc} = "modified";
            $rah_diff_L->[$n_sdiff]{lnum} = $n_L;
            $rah_diff_R->[$n_sdiff]{lnum} = $n_R;
#}

        } elsif ($flag eq '+') {  # + = added
            ++$n_R;
            if ($COMMENT_MODE) {
                # should never get here
                @{$rah_diff_L} = ();
                @{$rah_diff_R} = ();
                push @{$raa_Errors}, 
                     [ $Error_Codes{'Diff error (quoted comments?)'}, $file ];
                if ($opt_v) {
                  warn "array_diff: diff failure (diff says the\n";
                  warn "comment-free file has added lines).\n";
                  warn "$n_sdiff  $line_L\n";
                }
                last;
            }
            $rah_diff_L->[$n_sdiff]{type} = "nonexist";
            $rah_diff_L->[$n_sdiff]{desc} = "removed";
            $rah_diff_R->[$n_sdiff]{desc} = "added";
            $rah_diff_R->[$n_sdiff]{lnum} = $n_R;
        } elsif ($flag eq '-') {  # - = removed
            ++$n_L;
            if ($COMMENT_MODE) {
                # line must be comment because blanks already gone
                $rah_diff_L->[$n_sdiff]{type} = "comment";
            }
            $rah_diff_R->[$n_sdiff]{type} = "nonexist";
            $rah_diff_R->[$n_sdiff]{desc} = "removed";
            $rah_diff_L->[$n_sdiff]{desc} = "added";
            $rah_diff_L->[$n_sdiff]{lnum} = $n_L;
        }
#printf "%-30s %s %-30s\n", $line_L, $separator, $line_R;
        ++$n_sdiff;
    }
#use Data::Dumper::Simple;
#print Dumper($rah_diff_L, $rah_diff_R);

    print "<- array_diff\n" if $opt_v > 2;
} # 1}}}
sub remove_leading_dir {                     # {{{1 
    my @filenames = @_;
    #
    #  Input should be a list of file names
    #  with the same leading directory such as
    # 
    #      dir1/dir2/a.txt
    #      dir1/dir2/b.txt
    #      dir1/dir2/dir3/c.txt
    #
    #  Output is the same list minus the common
    #  directory path:
    # 
    #      a.txt
    #      b.txt
    #      dir3/c.txt
    #
    print "-> remove_leading_dir()\n" if $opt_v > 2;
    my @D = (); # a matrix:   [ [ dir1, dir2 ],         # dir1/dir2/a.txt
                #               [ dir1, dir2 ],         # dir1/dir2/b.txt
                #               [ dir1, dir2 , dir3] ]  # dir1/dir2/dir3/c.txt
    if ($ON_WINDOWS) {
        foreach my $F (@filenames) {
            $F =~ s{\\}{/}g;
            $F = ucfirst($F) if $F =~ /^\w:/;  # uppercase drive letter
        }
    }
    if (scalar @filenames == 1) {
        # special case:  with only one filename
        # cannot determine a baseline
        return ( basename $filenames[0] );
    }
    foreach my $F (@filenames) {
        my ($Vol, $Dir, $File) = File::Spec->splitpath($F);
        my @x = File::Spec->splitdir( $Dir );
        pop @x unless $x[$#x]; # last entry usually null, remove it
        if ($ON_WINDOWS) {
            if (defined($Vol) and $Vol) {
                # put the drive letter, eg, C:, at the front
                unshift @x, uc $Vol;
            }
        }
#print "F=$F, Dir=$Dir  x=[", join("][", @x), "]\n";
        push @D, [ @x ];
    }

    # now loop over columns until either they are all
    # eliminated or a unique column is found

#use Data::Dumper::Simple;
#print Dumper("remove_leading_dir after ", @D);

    my @common   = ();  # to contain the common leading directories
    my $mismatch = 0;
    while (!$mismatch) {
        for (my $row = 1; $row < scalar @D; $row++) {
#print "comparing $D[$row][0] to $D[0][0]\n";

            if (!defined $D[$row][0] or !defined $D[0][0] or
                ($D[$row][0] ne $D[0][0])) {
                $mismatch = 1;
                last;
            }
        }
#print "mismatch=$mismatch\n";
        if (!$mismatch) {
            push @common, $D[0][0];
            # all terms in the leading match; unshift the batch
            foreach my $ra (@D) {
                shift @{$ra};
            }
        }
    }

    push @common, " ";  # so that $leading will end with "/ "
    my $leading = File::Spec->catdir( @common );
       $leading =~ s{ $}{};  # now take back the bogus appended space
#print "remove_leading_dir leading=[$leading]\n"; die;
    if ($ON_WINDOWS) {
       $leading =~ s{\\}{/}g;
    }
    foreach my $F (@filenames) {
        $F =~ s{^$leading}{};
    }

    print "<- remove_leading_dir()\n" if $opt_v > 2;
    return @filenames;

} # 1}}}
sub align_by_pairs {                         # {{{1 
    my ($rh_file_list_L        , # in
        $rh_file_list_R        , # in
        $ra_added              , # out
        $ra_removed            , # out
        $ra_compare_list       , # out
        ) = @_;
    print "-> align_by_pairs()\n" if $opt_v > 2;
    @{$ra_compare_list} = ();

    my @files_L = sort keys %{$rh_file_list_L};
    my @files_R = sort keys %{$rh_file_list_R};
    return () unless @files_L or  @files_R;  # at least one must have stuff
    if      ( @files_L and !@files_R) {
        # left side has stuff, right side is empty; everything deleted
        @{$ra_added   }     = ();
        @{$ra_removed }     = @files_L;
        @{$ra_compare_list} = ();
        return;
    } elsif (!@files_L and  @files_R) {
        # left side is empty, right side has stuff; everything added
        @{$ra_added   }     = @files_R;
        @{$ra_removed }     = ();
        @{$ra_compare_list} = ();
        return;
    }
#use Data::Dumper::Simple;
#print Dumper("align_by_pairs", @files_L, @files_R);
#die;
    if (scalar @files_L == 1 and scalar @files_R == 1) {
        # The easy case:  compare two files.
        push @{$ra_compare_list}, [ $files_L[0],  $files_R[0] ]; 
        @{$ra_added  } = ();
        @{$ra_removed} = ();
        return;
    }
    # The harder case:  compare groups of files.  This only works
    # if the groups are in different directories so the first step
    # is to strip the leading directory names from file lists to
    # make it possible to align by file names.
    my @files_L_minus_dir = remove_leading_dir(@files_L);
    my @files_R_minus_dir = remove_leading_dir(@files_R);

    # Keys of the stripped_X arrays are canonical file names;
    # should overlap mostly.  Keys in stripped_L but not in
    # stripped_R are files that have been deleted.  Keys in
    # stripped_R but not in stripped_L have been added.
    my %stripped_L = ();
       @stripped_L{ @files_L_minus_dir } = @files_L;
    my %stripped_R = ();
       @stripped_R{ @files_R_minus_dir } = @files_R;

    my %common = ();
    foreach my $f (keys %stripped_L) {
        $common{$f}  = 1 if     defined $stripped_R{$f};
    }

    my %deleted = ();
    foreach my $f (keys %stripped_L) {
        $deleted{$stripped_L{$f}} = $f unless defined $stripped_R{$f};
    }

    my %added = ();
    foreach my $f (keys %stripped_R) {
        $added{$stripped_R{$f}}   = $f unless defined $stripped_L{$f};
    }

#use Data::Dumper::Simple;
#print Dumper("align_by_pairs", %stripped_L, %stripped_R);
#print Dumper("align_by_pairs", %common, %added, %deleted);
    
    foreach my $f (keys %common) {
        push @{$ra_compare_list}, [ $stripped_L{$f},  
                                    $stripped_R{$f} ]; 
    }
    @{$ra_added   } = keys %added  ;
    @{$ra_removed } = keys %deleted;

    print "<- align_by_pairs()\n" if $opt_v > 2;
    return;
#print Dumper("align_by_pairs", @files_L_minus_dir, @files_R_minus_dir);
#die;
} # 1}}}
sub html_header {                            # {{{1
    my ($title , ) = @_;

    print "-> html_header\n" if $opt_v > 2;
    return 
'<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1">
<meta name="GENERATOR" content="cloc http://cloc.sourceforge.net">
' .
"
<!-- Created by $script v$VERSION -->
<title>$title</title>
" .
'
<style TYPE="text/css">
<!--
    body {
        color: black;
        background-color: white;
        font-family: monospace
    }

    .whitespace {
        background-color: gray;
    }

    .comment {
        color: gray;
        font-style: italic;
    }

    .clinenum {
        color: red;
    }

    .linenum {
        color: green;
    }
 -->
</style>
</head>
<body>
<pre><tt>
';
    print "<- html_header\n" if $opt_v > 2;
} # 1}}}
sub html_end {                               # {{{1
return 
'</tt></pre>
</body>
</html>
';
} # 1}}}
sub die_unknown_lang {                       # {{{1
    my ($lang, $option_name) = @_;
    die "Unknown language '$lang' used with $option_name option.  " .
        "The command\n  $script --show-lang\n" .
        "will print all recognized languages.  Language names are " .
        "case sensitive.\n" ;
} # 1}}}
sub unicode_file {                           # {{{1
    my $file = shift @_; 

    print "-> unicode_file($file)\n" if $opt_v > 2;
    return 0 if (-s $file > 2_000_000);  
    # don't bother trying to test binary files bigger than 2 MB

    my $IN = new IO::File $file, "r";
    if (!defined $IN) {
        warn "Unable to read $file; ignoring.\n";
        return 0;
    }
    my @lines = <$IN>;
    $IN->close;

    if (unicode_to_ascii( join('', @lines) )) {
        print "<- unicode_file()\n" if $opt_v > 2;
        return 1;
    } else {
        print "<- unicode_file()\n" if $opt_v > 2;
        return 0;
    }

} # 1}}}
sub unicode_to_ascii {                       # {{{1
    my $string = shift @_; 

    # A trivial attempt to convert Microsoft Windows style Unicode
    # files into ASCII.  These files exhibit the following byte
    # sequence:
    # byte   1:  255
    # byte   2:  254
    # byte   3:  ord of ASCII character
    # byte   4:    0
    # byte 3+i:  ord of ASCII character
    # byte 4+i:    0

    my @ascii              = ();
    my $looks_like_unicode = 1;
    my $length             = length $string;
# print "length=$length\n";
    if ($length <= 3) {
        $looks_like_unicode = 0;
        return '';
    }
    my @unicode            = split(//, $string);

    for (my $i = 2; $i < $length; $i += 2) {
# print "examining [$unicode[$i]]  ord ", ord($unicode[$i]), "\n";
        if (32 <= ord($unicode[$i]) and ord($unicode[$i]) <= 127
            or ord($unicode[$i]) == 13
            or ord($unicode[$i]) == 10
            or ord($unicode[$i]) ==  9
            ) {
            push @ascii, $unicode[$i];
# print "adding [$unicode[$i]]\n";
        } else {
            $looks_like_unicode = 0;
            last;
        }
        if ($i+1 < $length) {
            if (!$unicode[$i+1]) {
                $looks_like_unicode = 0;
                last;
            }
        }
    }
    if ($looks_like_unicode) {
        return join("", @ascii);
    } else {
        return '';
    }
} # 1}}}
sub uncompress_archive_cmd {                 # {{{1
    my ($archive_file, ) = @_;

    # Wrap $archive_file in single or double quotes in the system
    # commands below to avoid filename chicanery (including
    # spaces in the names).

    print "-> uncompress_archive_cmd($archive_file)\n" if $opt_v > 2;
    my $extract_cmd = "";
    my $missing     = "";
    if ($opt_extract_with) {
        ( $extract_cmd = $opt_extract_with ) =~ s/>FILE</$archive_file/g;
    } elsif (($archive_file =~ /\.tar\.(gz|Z)$/ or 
              $archive_file =~ /\.tgz$/       ) and !$ON_WINDOWS)    {
        if (external_utility_exists("gzip --version")) {
            if (external_utility_exists("tar --version")) {
                $extract_cmd = "gzip -dc '$archive_file' | tar xf -";
            } else {
                $missing = "tar";
            }
        } else {
            $missing = "gzip";
        }
    } elsif ($archive_file =~ /\.tar\.bz2$/ and !$ON_WINDOWS)    {
        if (external_utility_exists("bzip2 --help")) {
            if (external_utility_exists("tar --version")) {
                $extract_cmd = "bzip2 -dc '$archive_file' | tar xf -";
            } else {
                $missing = "tar";
            }
        } else {
            $missing = "bzip2";
        }
    } elsif ($archive_file =~ /\.tar$/ and !$ON_WINDOWS)    {
        $extract_cmd = "tar xf '$archive_file'";
    } elsif ($archive_file =~ /\.src\.rpm$/i and !$ON_WINDOWS) {
        if (external_utility_exists("cpio --version")) {
            if (external_utility_exists("rpm2cpio")) {
                $extract_cmd = "rpm2cpio '$archive_file' | cpio -i";
            } else {
                $missing = "rpm2cpio";
            }
        } else {
            $missing = "bzip2";
        }
    } elsif ($archive_file =~ /\.zip$/i and !$ON_WINDOWS)    {
        if (external_utility_exists("unzip")) {
            $extract_cmd = "unzip -qq -d . '$archive_file'";
        } else {
            $missing = "unzip";
        }
    } elsif ($ON_WINDOWS and $archive_file =~ /\.zip$/i) {
        # zip on Windows, guess default Winzip install location
        $extract_cmd = "";
        my $WinZip = '"C:\\Program Files\\WinZip\\WinZip32.exe"';
        if (external_utility_exists($WinZip)) {
            $extract_cmd = "$WinZip -e -o \"$archive_file\" .";
#print "trace 5 extract_cmd=[$extract_cmd]\n";
        } else {
#print "trace 6\n";
            $missing = $WinZip;
        }
    }
    print "<- uncompress_archive_cmd\n" if $opt_v > 2;
    if ($missing) {
        die "Unable to expand $archive_file because external\n",
            "utility '$missing' is not available.\n",
            "Another possibility is to use the --extract-with option.\n";
    } else {
        return $extract_cmd;
    }
}
# 1}}}
sub read_list_file {                         # {{{1
    my ($file, ) = @_;

    print "-> read_list_file($file)\n" if $opt_v > 2;
    my $IN = new IO::File $file, "r";
    if (!defined $IN) {
        warn "Unable to read $file; ignoring.\n";
        next;
    }
    my @entry = ();
    while (<$IN>) {
        next if /^\s*$/ or /^\s*#/; # skip empty or commented lines
        chomp;
        push @entry, $_;
    }
    $IN->close;

    print "<- read_list_file\n" if $opt_v > 2;
    return @entry;
}
# 1}}}
sub external_utility_exists {                # {{{1
    my $exe = shift @_;

    my $success      = 0;
    if ($ON_WINDOWS) {
        $success = 1 unless system $exe . ' > nul';
    } else {
        $success = 1 unless system $exe . ' >& /dev/null';
        if (!$success) {
            $success = 1 unless system "which" . " $exe" . ' >& /dev/null';
        }
    }
    
    return $success;
} # 1}}}
sub write_xsl_file {                         # {{{1
    my $OUT = new IO::File $CLOC_XSL, "w";
    if (!defined $OUT) {
        warn "Unable to write $CLOC_XSL  $!\n";
        return;
    }
    my $XSL =             # <style>  </style> {{{2
'<?xml version="1.0" encoding="US-ASCII"?>
<!-- XLS file by Paul Schwann, January 2009.
     Fixes for by-file and by-file-by-lang by d_uragan, November 2010.
     -->
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="html"/>
  <xsl:template match="/">
    <html xmlns="http://www.w3.org/1999/xhtml">
      <head>
        <title>CLOC Results</title>
      </head>
      <style type="text/css">
        table {
          table-layout: auto;
          border-collapse: collapse;
          empty-cells: show;
        }
        td, th {
          padding: 4px;
        }
        th {
          background-color: #CCCCCC;
        }
        td {
          text-align: center;
        }
        table, td, tr, th {
          border: thin solid #999999;
        }
      </style>
      <body>
        <h3><xsl:value-of select="results/header"/></h3>
';
# 2}}}

    if ($opt_by_file) {
        $XSL .=             # <table> </table>{{{2
'        <table>
          <thead>
            <tr>
              <th>File</th>
              <th>Blank</th>
              <th>Comment</th>
              <th>Code</th>
              <th>Language</th>
';
        $XSL .=
'             <th>3<sup>rd</sup> Generation Equivalent</th>
              <th>Scale</th>
' if $opt_3;
        $XSL .=
'           </tr>
          </thead>
          <tbody>
          <xsl:for-each select="results/files/file">
            <tr>
              <th><xsl:value-of select="@name"/></th>
              <td><xsl:value-of select="@blank"/></td>
              <td><xsl:value-of select="@comment"/></td>
              <td><xsl:value-of select="@code"/></td>
              <td><xsl:value-of select="@language"/></td>
';
        $XSL .=
'             <td><xsl:value-of select="@factor"/></td>
              <td><xsl:value-of select="@scaled"/></td>
' if $opt_3;
        $XSL .=
'           </tr>
          </xsl:for-each>
            <tr>
              <th>Total</th>
              <th><xsl:value-of select="results/files/total/@blank"/></th>
              <th><xsl:value-of select="results/files/total/@comment"/></th>
              <th><xsl:value-of select="results/files/total/@code"/></th>
              <th><xsl:value-of select="results/files/total/@language"/></th>
';
        $XSL .=
'             <th><xsl:value-of select="results/files/total/@factor"/></th>
              <th><xsl:value-of select="results/files/total/@scaled"/></th>
' if $opt_3;
        $XSL .=
'           </tr>
          </tbody>
        </table>
        <br/>
';
# 2}}}
    }

    if (!$opt_by_file or $opt_by_file_by_lang) {
        $XSL .=             # <table> </table> {{{2
'       <table>
          <thead>
            <tr>
              <th>Language</th>
              <th>Files</th>
              <th>Blank</th>
              <th>Comment</th>
              <th>Code</th>
';
        $XSL .=
'             <th>Scale</th>
              <th>3<sup>rd</sup> Generation Equivalent</th>
' if $opt_3;
        $XSL .=
'           </tr>
          </thead>
          <tbody>
          <xsl:for-each select="results/languages/language">
            <tr>
              <th><xsl:value-of select="@name"/></th>
              <td><xsl:value-of select="@files_count"/></td>
              <td><xsl:value-of select="@blank"/></td>
              <td><xsl:value-of select="@comment"/></td>
              <td><xsl:value-of select="@code"/></td>
';
        $XSL .=
'             <td><xsl:value-of select="@factor"/></td>
              <td><xsl:value-of select="@scaled"/></td>
' if $opt_3;
        $XSL .=
'          </tr>
          </xsl:for-each>
            <tr>
              <th>Total</th>
              <th><xsl:value-of select="results/languages/total/@sum_files"/></th>
              <th><xsl:value-of select="results/languages/total/@blank"/></th>
              <th><xsl:value-of select="results/languages/total/@comment"/></th>
              <th><xsl:value-of select="results/languages/total/@code"/></th>
';
        $XSL .=
'             <th><xsl:value-of select="results/languages/total/@factor"/></th>
              <th><xsl:value-of select="results/languages/total/@scaled"/></th>
' if $opt_3;
        $XSL .=
'           </tr>
          </tbody>
        </table>
';
# 2}}}
    }

    $XSL.= <<'EO_XSL'; # {{{2
      </body>
    </html>
  </xsl:template>
</xsl:stylesheet>

EO_XSL
# 2}}}

    my $XSL_DIFF = <<'EO_DIFF_XSL'; # {{{2
<?xml version="1.0" encoding="US-ASCII"?>
<!-- XLS file by Blazej Kroll, November 2010 -->
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="html"/>
  <xsl:template match="/">
    <html xmlns="http://www.w3.org/1999/xhtml">
      <head>
        <title>CLOC Results</title>
      </head>
      <style type="text/css">
        table {
          table-layout: auto;
          border-collapse: collapse;
          empty-cells: show;
		  margin: 1em;
        }
        td, th {
          padding: 4px;
        }
        th {
          background-color: #CCCCCC;
        }
        td {
          text-align: center;
        }
        table, td, tr, th {
          border: thin solid #999999;
        }
      </style>
      <body>
        <h3><xsl:value-of select="results/header"/></h3>
EO_DIFF_XSL
# 2}}}

    if ($opt_by_file) {
        $XSL_DIFF.= <<'EO_DIFF_XSL'; # {{{2
		<table>
          <thead>
		  <tr><th colspan="4">Same</th>
		  </tr>
            <tr>
              <th>File</th>
              <th>Blank</th>
              <th>Comment</th>
              <th>Code</th>              
            </tr>
          </thead>
          <tbody>
          <xsl:for-each select="diff_results/same/file">
            <tr>
              <th><xsl:value-of select="@name"/></th>
              <td><xsl:value-of select="@blank"/></td>
              <td><xsl:value-of select="@comment"/></td>
              <td><xsl:value-of select="@code"/></td>              
            </tr>
          </xsl:for-each>            
          </tbody>
        </table>
		
		<table>
          <thead>
		  <tr><th colspan="4">Modified</th>
		  </tr>
            <tr>
              <th>File</th>
              <th>Blank</th>
              <th>Comment</th>
              <th>Code</th>              
            </tr>
          </thead>
          <tbody>
          <xsl:for-each select="diff_results/modified/file">
            <tr>
              <th><xsl:value-of select="@name"/></th>
              <td><xsl:value-of select="@blank"/></td>
              <td><xsl:value-of select="@comment"/></td>
              <td><xsl:value-of select="@code"/></td>              
            </tr>
          </xsl:for-each>            
          </tbody>
        </table>
		
		<table>
          <thead>
		  <tr><th colspan="4">Added</th>
		  </tr>
            <tr>
              <th>File</th>
              <th>Blank</th>
              <th>Comment</th>
              <th>Code</th>              
            </tr>
          </thead>
          <tbody>
          <xsl:for-each select="diff_results/added/file">
            <tr>
              <th><xsl:value-of select="@name"/></th>
              <td><xsl:value-of select="@blank"/></td>
              <td><xsl:value-of select="@comment"/></td>
              <td><xsl:value-of select="@code"/></td>              
            </tr>
          </xsl:for-each>            
          </tbody>
        </table>
		
		<table>
          <thead>
		  <tr><th colspan="4">Removed</th>
		  </tr>
            <tr>
              <th>File</th>
              <th>Blank</th>
              <th>Comment</th>
              <th>Code</th>              
            </tr>
          </thead>
          <tbody>
          <xsl:for-each select="diff_results/removed/file">
            <tr>
              <th><xsl:value-of select="@name"/></th>
              <td><xsl:value-of select="@blank"/></td>
              <td><xsl:value-of select="@comment"/></td>
              <td><xsl:value-of select="@code"/></td>              
            </tr>
          </xsl:for-each>            
          </tbody>
        </table>
EO_DIFF_XSL
# 2}}}
    }

    if (!$opt_by_file or $opt_by_file_by_lang) {
        $XSL_DIFF.= <<'EO_DIFF_XSL'; # {{{2
		<table>
          <thead>
		  <tr><th colspan="5">Same</th>
		  </tr>
            <tr>
              <th>Language</th>
              <th>Files</th>
              <th>Blank</th>
              <th>Comment</th>
              <th>Code</th>              
            </tr>
          </thead>
          <tbody>
          <xsl:for-each select="diff_results/same/language">
            <tr>
              <th><xsl:value-of select="@name"/></th>
              <td><xsl:value-of select="@files_count"/></td>
              <td><xsl:value-of select="@blank"/></td>
              <td><xsl:value-of select="@comment"/></td>
              <td><xsl:value-of select="@code"/></td>              
            </tr>
          </xsl:for-each>            
          </tbody>
        </table>
		
		<table>
          <thead>
		  <tr><th colspan="5">Modified</th>
		  </tr>
            <tr>
              <th>Language</th>
              <th>Files</th>
              <th>Blank</th>
              <th>Comment</th>
              <th>Code</th>              
            </tr>
          </thead>
          <tbody>
          <xsl:for-each select="diff_results/modified/language">
            <tr>
              <th><xsl:value-of select="@name"/></th>
              <td><xsl:value-of select="@files_count"/></td>
              <td><xsl:value-of select="@blank"/></td>
              <td><xsl:value-of select="@comment"/></td>
              <td><xsl:value-of select="@code"/></td>              
            </tr>
          </xsl:for-each>            
          </tbody>
        </table>
		
		<table>
          <thead>
		  <tr><th colspan="5">Added</th>
		  </tr>
            <tr>
              <th>Language</th>
              <th>Files</th>
              <th>Blank</th>
              <th>Comment</th>
              <th>Code</th>              
            </tr>
          </thead>
          <tbody>
          <xsl:for-each select="diff_results/added/language">
            <tr>
              <th><xsl:value-of select="@name"/></th>
              <td><xsl:value-of select="@files_count"/></td>
              <td><xsl:value-of select="@blank"/></td>
              <td><xsl:value-of select="@comment"/></td>
              <td><xsl:value-of select="@code"/></td>              
            </tr>
          </xsl:for-each>            
          </tbody>
        </table>
		
		<table>
          <thead>
		  <tr><th colspan="5">Removed</th>
		  </tr>
            <tr>
              <th>Language</th>
              <th>Files</th>
              <th>Blank</th>
              <th>Comment</th>
              <th>Code</th>              
            </tr>
          </thead>
          <tbody>
          <xsl:for-each select="diff_results/removed/language">
            <tr>
              <th><xsl:value-of select="@name"/></th>
              <td><xsl:value-of select="@files_count"/></td>
              <td><xsl:value-of select="@blank"/></td>
              <td><xsl:value-of select="@comment"/></td>
              <td><xsl:value-of select="@code"/></td>              
            </tr>
          </xsl:for-each>            
          </tbody>
        </table>
EO_DIFF_XSL
# 2}}}

    }
    
    $XSL_DIFF.= <<'EO_DIFF_XSL'; # {{{2
      </body>
    </html>
  </xsl:template>
</xsl:stylesheet>
EO_DIFF_XSL
# 2}}}
    if ($opt_diff) {
        print $OUT $XSL_DIFF;
    } else {
        print $OUT $XSL;
    }
    $OUT->close();
} # 1}}}
sub normalize_file_names {                   # {{{1 
    my (@files, ) = @_;

    # Returns a hash of file names reduced to a canonical form
    # (fully qualified file names, all path separators changed to /,
    # Windows file names lowercased).  Hash values are the original
    # file name.

    my %normalized = ();
    foreach my $F (@files) {
        my $F_norm = $F;
        if ($ON_WINDOWS) {
            $F_norm = lc $F_norm; # for case insensitive file name comparisons
            $F_norm =~ s{\\}{/}g; # Windows directory separators to Unix
            $F_norm =~ s{^\./}{}g;  # remove leading ./
            if (($F_norm !~ m{^/}) and ($F_norm !~ m{^\w:/})) {
                # looks like a relative path; prefix with cwd
                $F_norm = lc "$cwd/$F_norm";
            }
        } else {
            $F_norm =~ s{^\./}{}g;  # remove leading ./
            if ($F_norm !~ m{^/}) {
                # looks like a relative path; prefix with cwd
                $F_norm = lc "$cwd/$F_norm";
            }
        }
        $normalized{ $F_norm } = $F;
    }
    return %normalized;
} # 1}}}
sub combine_diffs {                          # {{{1
    # subroutine by Andy (awalshe@sf.net)
    # https://sourceforge.net/tracker/?func=detail&aid=3261017&group_id=174787&atid=870625
    my ($ra_files) = @_;

    my $res   = "$URL v $VERSION\n";
    my $dl    = '-';
    my $width = 79;
    # columns are in this order
    my @cols  = ('files', 'blank', 'comment', 'code');
    my %HoH   = ();
  
    foreach my $file (@{$ra_files}) {
        my $IN = new IO::File $file, "r";
        if (!defined $IN) {
            warn "Unable to read $file; ignoring.\n";
            next;
        }

        my $sec;
        while (<$IN>) {
            next if /^(http|Language|-----)/;
            if (/^[A-Z][a-z]*/) {        # section title
                $sec = $_;
                chomp($sec);
                $HoH{$sec} = () if ! exists $HoH{$sec};
                next;
            }
  
            if (/^\s(same|modified|added|removed)/) {  # calculated totals row
                my @ar = grep { $_ ne '' } split(/ /, $_);
                chomp(@ar);
                my $ttl = shift @ar;
                my $i = 0;
                foreach(@ar) {
                    my $t = "$ttl$dl$cols[$i]";
                    $HoH{$sec}{$t} = 0 if ! exists $HoH{$sec}{$t};
                    $HoH{$sec}{$t} += $_;
                    $i++;
                }
            }
        }
        $IN->close;
    }
  
    # rows are in this order
    my @rows = ('same', 'modified', 'added', 'removed');
  
    $res .= sprintf("%s\n", "-" x $width);
    $res .= sprintf("%-19s %14s %14s %14s %14s\n", 'Language', 
                    $cols[0], $cols[1], $cols[2], $cols[3]);
    $res .= sprintf("%s\n", "-" x $width);
  
    for my $sec ( keys %HoH ) {
        next if $sec =~ /SUM:/;
        $res .= "$sec\n";
        foreach (@rows) {
            $res .= sprintf(" %-18s %14s %14s %14s %14s\n", 
                            $_, $HoH{$sec}{"$_$dl$cols[0]"},
                                $HoH{$sec}{"$_$dl$cols[1]"},
                                $HoH{$sec}{"$_$dl$cols[2]"},
                                $HoH{$sec}{"$_$dl$cols[3]"});
        }
    }
    $res .= sprintf("%s\n", "-" x $width);
    my $sec = 'SUM:';
    $res .= "$sec\n";
    foreach (@rows) {
        $res .= sprintf(" %-18s %14s %14s %14s %14s\n", 
                        $_, $HoH{$sec}{"$_$dl$cols[0]"},
                            $HoH{$sec}{"$_$dl$cols[1]"},
                            $HoH{$sec}{"$_$dl$cols[2]"},
                            $HoH{$sec}{"$_$dl$cols[3]"});
    }
    $res .= sprintf("%s\n", "-" x $width);
  
    return $res;
} # 1}}}
# subroutines copied from SLOCCount
my %lex_files    = ();  # really_is_lex()
my %expect_files = ();  # really_is_expect()
my %pascal_files = ();  # really_is_pascal(), really_is_incpascal()
my %php_files    = ();  # really_is_php()
sub really_is_lex {                          # {{{1
# Given filename, returns TRUE if its contents really is lex.
# lex file must have "%%", "%{", and "%}".
# In theory, a lex file doesn't need "%{" and "%}", but in practice
# they all have them, and requiring them avoid mislabeling a
# non-lexfile as a lex file.

 my $filename = shift;
 chomp($filename);

 my $is_lex = 0;      # Value to determine.
 my $percent_percent = 0;
 my $percent_opencurly = 0;
 my $percent_closecurly = 0;

 # Return cached result, if available:
 if ($lex_files{$filename}) { return $lex_files{$filename};}

 open(LEX_FILE, "<$filename") ||
      die "Can't open $filename to determine if it's lex.\n";
 while(<LEX_FILE>) {
   $percent_percent++     if (m/^\s*\%\%/);
   $percent_opencurly++   if (m/^\s*\%\{/);
   $percent_closecurly++   if (m/^\s*\%\}/);
 }
 close(LEX_FILE);

 if ($percent_percent && $percent_opencurly && $percent_closecurly)
          {$is_lex = 1;}

 $lex_files{$filename} = $is_lex; # Store result in cache.

 return $is_lex;
} # 1}}}
sub really_is_expect {                       # {{{1
# Given filename, returns TRUE if its contents really are Expect.
# Many "exp" files (such as in Apache and Mesa) are just "export" data,
# summarizing something else # (e.g., its interface).
# Sometimes (like in RPM) it's just misc. data.
# Thus, we need to look at the file to determine
# if it's really an "expect" file.

 my $filename = shift;
 chomp($filename);

# The heuristic is as follows: it's Expect _IF_ it:
# 1. has "load_lib" command and either "#" comments or {}.
# 2. {, }, and one of: proc, if, [...], expect

 my $is_expect = 0;      # Value to determine.

 my $begin_brace = 0;  # Lines that begin with curly braces.
 my $end_brace = 0;    # Lines that begin with curly braces.
 my $load_lib = 0;     # Lines with the Load_lib command.
 my $found_proc = 0;
 my $found_if = 0;
 my $found_brackets = 0;
 my $found_expect = 0;
 my $found_pound = 0;

 # Return cached result, if available:
 if ($expect_files{$filename}) { return expect_files{$filename};}

 open(EXPECT_FILE, "<$filename") ||
      die "Can't open $filename to determine if it's expect.\n";
 while(<EXPECT_FILE>) {

   if (m/#/) {$found_pound++; s/#.*//;}
   if (m/^\s*\{/) { $begin_brace++;}
   if (m/\{\s*$/) { $begin_brace++;}
   if (m/^\s*\}/) { $end_brace++;}
   if (m/\};?\s*$/) { $end_brace++;}
   if (m/^\s*load_lib\s+\S/) { $load_lib++;}
   if (m/^\s*proc\s/) { $found_proc++;}
   if (m/^\s*if\s/) { $found_if++;}
   if (m/\[.*\]/) { $found_brackets++;}
   if (m/^\s*expect\s/) { $found_expect++;}
 }
 close(EXPECT_FILE);

 if ($load_lib && ($found_pound || ($begin_brace && $end_brace)))
          {$is_expect = 1;}
 if ( $begin_brace && $end_brace &&
      ($found_proc || $found_if || $found_brackets || $found_expect))
          {$is_expect = 1;}

 $expect_files{$filename} = $is_expect; # Store result in cache.

 return $is_expect;
} # 1}}}
sub really_is_pascal {                       # {{{1
# Given filename, returns TRUE if its contents really are Pascal.

# This isn't as obvious as it seems.
# Many ".p" files are Perl files
# (such as /usr/src/redhat/BUILD/ispell-3.1/dicts/czech/glob.p),
# others are C extractions
# (such as /usr/src/redhat/BUILD/linux/include/linux/umsdos_fs.p
# and some files in linuxconf).
# However, test files in "p2c" really are Pascal, for example.

# Note that /usr/src/redhat/BUILD/ucd-snmp-4.1.1/ov/bitmaps/UCD.20.p
# is actually C code.  The heuristics determine that they're not Pascal,
# but because it ends in ".p" it's not counted as C code either.
# I believe this is actually correct behavior, because frankly it
# looks like it's automatically generated (it's a bitmap expressed as code).
# Rather than guess otherwise, we don't include it in a list of
# source files.  Let's face it, someone who creates C files ending in ".p"
# and expects them to be counted by default as C files in SLOCCount needs
# their head examined.  I suggest examining their head
# with a sucker rod (see syslogd(8) for more on sucker rods).

# This heuristic counts as Pascal such files such as:
#  /usr/src/redhat/BUILD/teTeX-1.0/texk/web2c/tangleboot.p
# Which is hand-generated.  We don't count woven documents now anyway,
# so this is justifiable.

 my $filename = shift;
 chomp($filename);

# The heuristic is as follows: it's Pascal _IF_ it has all of the following
# (ignoring {...} and (*...*) comments):
# 1. "^..program NAME" or "^..unit NAME",
# 2. "procedure", "function", "^..interface", or "^..implementation",
# 3. a "begin", and
# 4. it ends with "end.",
#
# Or it has all of the following:
# 1. "^..module NAME" and
# 2. it ends with "end.".
#
# Or it has all of the following:
# 1. "^..program NAME",
# 2. a "begin", and
# 3. it ends with "end.".
#
# The "end." requirements in particular filter out non-Pascal.
#
# Note (jgb): this does not detect Pascal main files in fpc, like
# fpc-1.0.4/api/test/testterminfo.pas, which does not have "program" in
# it

 my $is_pascal = 0;      # Value to determine.

 my $has_program = 0;
 my $has_unit = 0;
 my $has_module = 0;
 my $has_procedure_or_function = 0;
 my $found_begin = 0;
 my $found_terminating_end = 0;
 my $has_begin = 0;

 # Return cached result, if available:
 if ($pascal_files{$filename}) { return pascal_files{$filename};}

 open(PASCAL_FILE, "<$filename") ||
      die "Can't open $filename to determine if it's pascal.\n";
 while(<PASCAL_FILE>) {
   s/\{.*?\}//g;  # Ignore {...} comments on this line; imperfect, but effective.
   s/\(\*.*?\*\)//g;  # Ignore (*...*) comments on this line; imperfect, but effective.
   if (m/\bprogram\s+[A-Za-z]/i)  {$has_program=1;}
   if (m/\bunit\s+[A-Za-z]/i)     {$has_unit=1;}
   if (m/\bmodule\s+[A-Za-z]/i)   {$has_module=1;}
   if (m/\bprocedure\b/i)         { $has_procedure_or_function = 1; }
   if (m/\bfunction\b/i)          { $has_procedure_or_function = 1; }
   if (m/^\s*interface\s+/i)      { $has_procedure_or_function = 1; }
   if (m/^\s*implementation\s+/i) { $has_procedure_or_function = 1; }
   if (m/\bbegin\b/i) { $has_begin = 1; }
   # Originally I said:
   # "This heuristic fails if there are multi-line comments after
   # "end."; I haven't seen that in real Pascal programs:"
   # But jgb found there are a good quantity of them in Debian, specially in 
   # fpc (at the end of a lot of files there is a multiline comment
   # with the changelog for the file).
   # Therefore, assume Pascal if "end." appears anywhere in the file.
   if (m/end\.\s*$/i) {$found_terminating_end = 1;}
#   elsif (m/\S/) {$found_terminating_end = 0;}
 }
 close(PASCAL_FILE);

 # Okay, we've examined the entire file looking for clues;
 # let's use those clues to determine if it's really Pascal:

 if ( ( ($has_unit || $has_program) && $has_procedure_or_function &&
     $has_begin && $found_terminating_end ) ||
      ( $has_module && $found_terminating_end ) ||
      ( $has_program && $has_begin && $found_terminating_end ) )
          {$is_pascal = 1;}

 $pascal_files{$filename} = $is_pascal; # Store result in cache.

 return $is_pascal;
} # 1}}}
sub really_is_incpascal {                    # {{{1
# Given filename, returns TRUE if its contents really are Pascal.
# For .inc files (mainly seen in fpc)

 my $filename = shift;
 chomp($filename);

# The heuristic is as follows: it is Pacal if any of the following:
# 1. really_is_pascal returns true
# 2. Any usual reserved word is found (program, unit, const, begin...)

 # If the general routine for Pascal files works, we have it
 if (&really_is_pascal ($filename)) { 
   $pascal_files{$filename} = 1;
   return 1;
 }

 my $is_pascal = 0;      # Value to determine.
 my $found_begin = 0;

 open(PASCAL_FILE, "<$filename") ||
      die "Can't open $filename to determine if it's pascal.\n";
 while(<PASCAL_FILE>) {
   s/\{.*?\}//g;  # Ignore {...} comments on this line; imperfect, but effective.
   s/\(\*.*?\*\)//g;  # Ignore (*...*) comments on this line; imperfect, but effective.
   if (m/\bprogram\s+[A-Za-z]/i)  {$is_pascal=1;}
   if (m/\bunit\s+[A-Za-z]/i)     {$is_pascal=1;}
   if (m/\bmodule\s+[A-Za-z]/i)   {$is_pascal=1;}
   if (m/\bprocedure\b/i)         {$is_pascal = 1; }
   if (m/\bfunction\b/i)          {$is_pascal = 1; }
   if (m/^\s*interface\s+/i)      {$is_pascal = 1; }
   if (m/^\s*implementation\s+/i) {$is_pascal = 1; }
   if (m/\bconstant\s+/i)         {$is_pascal=1;}
   if (m/\bbegin\b/i) { $found_begin = 1; }
   if ((m/end\.\s*$/i) && ($found_begin = 1)) {$is_pascal = 1;}
   if ($is_pascal) {
     last;
   }
 }

 close(PASCAL_FILE);
 $pascal_files{$filename} = $is_pascal; # Store result in cache.
 return $is_pascal;
} # 1}}}
sub really_is_php {                          # {{{1
# Given filename, returns TRUE if its contents really is php.

 my $filename = shift;
 chomp($filename);

 my $is_php = 0;      # Value to determine.
 # Need to find a matching pair of surrounds, with ending after beginning:
 my $normal_surround = 0;  # <?; bit 0 = <?, bit 1 = ?>
 my $script_surround = 0;  # <script..>; bit 0 = <script language="php">
 my $asp_surround = 0;     # <%; bit 0 = <%, bit 1 = %>

 # Return cached result, if available:
 if ($php_files{$filename}) { return $php_files{$filename};}

 open(PHP_FILE, "<$filename") ||
      die "Can't open $filename to determine if it's php.\n";
 while(<PHP_FILE>) {
   if (m/\<\?/)                           { $normal_surround |= 1; }
   if (m/\?\>/ && ($normal_surround & 1)) { $normal_surround |= 2; }
   if (m/\<script.*language="?php"?/i)    { $script_surround |= 1; }
   if (m/\<\/script\>/i && ($script_surround & 1)) { $script_surround |= 2; }
   if (m/\<\%/)                           { $asp_surround |= 1; }
   if (m/\%\>/ && ($asp_surround & 1)) { $asp_surround |= 2; }
 }
 close(PHP_FILE);

 if ( ($normal_surround == 3) || ($script_surround == 3) ||
      ($asp_surround == 3)) {
   $is_php = 1;
 }

 $php_files{$filename} = $is_php; # Store result in cache.

 return $is_php;
} # 1}}}
__END__
mode values (stat $item)[2]
       Unix    Windows
file:  33188   33206
dir :  16832   16895
link:  33261   33206
pipe:   4544    null
