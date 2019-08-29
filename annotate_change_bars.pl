#!/usr/bin/perl
# annotate_change_bars.pl - add navigational aids to PDF files that contain change bars
#
# v0.1  chrispy  8/19/2016
#  prerelease
# v0.2  chrispy  8/31/2016
#  handle PDFs with no change bars properly
# v0.3  chrispy  9/20/2016
#  fix bug with custom margins
#  fix bug with choosing first/next in link text
#  handle arbitrary page sizes (besides 8.5x11)
# v0.4  chrispy  12/4/2017
#  support Win10 WSL
#    (sudo apt install ghostscript imagemagick poppler-utils)
#  fix incorrect DPI scaling factor in cropping code
# v0.5  chrispy  08/30/2018
#  improve usability of links along bottom
# v0.6  chrispy  08/29/2019
#  add real command-line parsing
#  suppress harmless warning from 'convert'
#  fix bug with paths with directories


use strict;
use POSIX;
use Getopt::Long 'HelpMessage';
use List::Util qw(min);
use File::Basename;

my $gs = (grep {-e $_} ('/usr/bin/gs', '/depot/ghostscript-9.18/bin/gs'))[0];  # use the first file that exists
my $TMPDIR = (grep {-e $_} ('/SCRATCH', '/tmp'))[0];  # use the first directory that exists
my $dpi = 36;

# define the change bar bounding box, in inches, from the upper-left corner
my $x1 = 0.500;
my $x2 = 0.875;
my $y1 = 1.0;
my $y2 = 10.0;

# process command-line arguments
my $new_pdf_file;
GetOptions(
  'output=s' => \$new_pdf_file,
  'help'         => sub { HelpMessage(0) }
  ) or HelpMessage(1);
my $pdf_file = shift or HelpMessage(1);
$new_pdf_file = $pdf_file if !defined($new_pdf_file);  ;# default to modifying file in-place

# get information about this PDF
my $pdf_info = `pdfinfo $pdf_file 2>&1`;

# don't process if produced by Ghostscript (which implies it's already processed)
if ($pdf_info =~ /^Producer:\s+GPL Ghostscript/m) {
 print "Keeping existing change bar annotations.\n";
 exit 0;
}

# get PDF filename info
my ($base, $path, $suffix) = fileparse($pdf_file, qr/\.pdf$/i);

# create multipage TIFF of change bars
print "Getting change bar information from PDF...\n";
my ($page_height_pts) = ($pdf_info =~ /Page size:.* x (\S+) pts/m);


my $full_pxwidth = ceil(($x2-$x1)*$dpi);  # these page width and height values here are in DPI-adjusted pixels
my $full_pxheight = ceil(($y2-$y1)*$dpi);

my $from_left = -floor($x1*72.0);  # the PDF crop values are always in points
my $from_bottom = -floor((($page_height_pts/72.0)-$y2)*72.0);  # (ditto)

print "  Creating multipage TIFF image file for change bars...\n";
system "$gs -q -sDEVICE=tiffgray -r${dpi} -o $TMPDIR/${base}.tiff -g${full_pxwidth}x${full_pxheight} -c \"<</Install {${from_left} ${from_bottom} translate}>> setpagedevice\" -f $pdf_file";

# get change bar data
print "  Getting change bar heights...\n";
my $cmd;
if (`uname -a` =~ m/-Microsoft/) {
 $cmd = "convert $TMPDIR/${base}.tiff -trim -format '%s %h\n' info:";  # Windows/WSL (needs linefeed - BUG)
} else {
 $cmd = "convert $TMPDIR/${base}.tiff -trim -format '%s %h' info:";  # linux (no linefeed)
}

# try to suppress harmless message:
#  'convert-im6.q16: geometry does not contain image `/tmp/test.tiff' @ warning/attribute.c/GetImageBoundingBox/247.' message
$cmd = "sh -c \"$cmd\ 2>&1 | grep -v 'geometry does not contain'\"";

my @changed_pages = ();
foreach my $line (split /^/, `$cmd`) {
 chomp $line;
 my ($pagenum, $bar_height) = (split(/ /, $line));
 $pagenum++;  # image numbers start at 0, PDF page numbers start at 1
 if ($bar_height != $full_pxheight && $bar_height != 1) {
  push @changed_pages, $pagenum;  # this page has a change bar
 }
}
unlink "$TMPDIR/${base}.tiff" or die "Unable to unlink $TMPDIR/${base}.tiff: $!";;

if (!@changed_pages) {
 print "No change bars found; keeping original PDF.\n";
 exit 0;
}
print "    Total changed pages detected: ".scalar(@changed_pages)."\n";
print "      ".join(' ', @changed_pages)."\n";


# gather data about the changes
my %next_page = ();  # for each changed page, this is the next page to jump to
my @sections = ();  # array of section page number arrays, e.g. ( [1 2] [4 5 6] [8] [11] )
{
 my $current_pages;
 my $last_pg;
 foreach my $pg (@changed_pages) {
  $next_page{$last_pg} = $pg if defined($last_pg);
  push @sections, ($current_pages = []) if ($pg != ($last_pg+1));
  push @{$current_pages}, $pg;
  $last_pg = $pg;
 }
}

print "    Total change sections: ".scalar(@sections)."\n";
foreach my $s (@sections) {
 print "      ".join(' ', @{$s})."\n";
}

# create annotation file
my $view = "/View [/XYZ 0 ${page_height_pts} 0]";  # upper-left of page at same zoom
my $full_ann_bbox = get_annotation_bbox(-1);  # get a full-width annotation box

open(FILE, ">$TMPDIR/${base}_ann.txt");
print FILE "[  /Title (CHANGE BAR REVIEWS) /Page 0 /Count ".scalar(@sections)." /OUT pdfmark\n";

# write change bar TOC bookmarks
my $i = 1;
foreach my $section (@sections) {
 my $first_page = @{$section}[0];
 my $last_page = @{$section}[-1] if (scalar(@{$section}) > 1);
 my $title = (defined($last_page)) ?
  "#".$i++." - pp. $first_page-$last_page" :
  "#".$i++." - p. $first_page";
 print FILE "[  /Title ($title) /Page $first_page $view /OUT pdfmark\n";
}

# write change bar links
my $pages_left = scalar(@changed_pages);
if ($changed_pages[0] > 1) {
 print FILE "[ /SrcPg 1 /Subtype /Link /Page $changed_pages[0] /Rect [ $full_ann_bbox ] /Color [ 1 0.25 0.25 ] /BS << /W 2 >> $view /ANN pdfmark\n";
 print FILE "[ /SrcPg 1 /Contents ($pages_left pages left\n(Go to first change)) /Rect [ ".get_annotation_bbox(0.0)." ] /Q 1 /DA ([0 0 0] rg /HeBo 11 Tf) /BS << /W 3 >> /Subtype /FreeText /ANN pdfmark\n";
}
foreach my $page (@changed_pages) {
 $pages_left--;
 if ($page < $changed_pages[-1]) {
  print FILE "[ /SrcPg $page /Subtype /Link /Page $next_page{$page} /Rect [ $full_ann_bbox ] /Color [ 1 0.25 0.25 ] /BS << /W 2 >> $view /ANN pdfmark\n";
  if ($next_page{$page} != $page+1) {
   print FILE "[ /SrcPg $page /Contents ($pages_left pages left\n(Go to next section)) /Rect [ ".get_annotation_bbox(1.0 - ($pages_left / (scalar(@changed_pages)-1)))." ] /Q 1 /DA ([0 0 0] rg /HeBo 11 Tf) /BS << /W 3 >> /Subtype /FreeText /ANN pdfmark\n";
  } else {
   print FILE "[ /SrcPg $page /Contents ($pages_left pages left) /Rect [ ".get_annotation_bbox(1.0 - ($pages_left / (scalar(@changed_pages)-1)))." ] /Q 1 /DA ([0.7 0.7 0.7] rg /HeBo 11 Tf) /BS << /W 3 >> /Subtype /FreeText /ANN pdfmark\n";
  }
 } else {
  print FILE "[ /SrcPg $page /Subtype /Link /Page $changed_pages[0] /Rect [ $full_ann_bbox ] /Color [ 0.25 1 0.25 ] /BS << /W 2 >> $view /ANN pdfmark\n";
  print FILE "[ /SrcPg $page /Contents (Review finished!\n(go to first change)) /Rect [ ".get_annotation_bbox(1.0)." ] /Q 1 /DA ([0 0 0] rg /HeBo 11 Tf) /BS << /W 3 >> /Subtype /FreeText /ANN pdfmark\n";
 }
}
close(FILE);

print "Creating annotated PDF file '$new_pdf_file'...\n";
my $temp_pdf_file = "${path}/${base}_temp${suffix}";
my $rc = system ("$gs -q -o ${temp_pdf_file} -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress $TMPDIR/${base}_ann.txt ${pdf_file}");
unlink "$TMPDIR/${base}_ann.txt";
if ($rc != 0) {unlink "$temp_pdf_file"; die "Ghostscript failed with return code $rc";}
rename $temp_pdf_file, $new_pdf_file;



sub get_annotation_bbox {
 my $percentage = shift(@_);

 # annotation box size, in points
 my $ann_width = 120;
 my $ann_height = 36;
 my $ann_margin = 3;

 my $page_width = (8.5 * 72);

 if ($percentage == -1) {$ann_width = ($page_width - ($ann_margin*2));}
 my $x_position = $ann_margin + int(($page_width - ($ann_margin*2) - $ann_width) * $percentage);
 
 return join(' ', $x_position, $ann_margin, $x_position+$ann_width, $ann_margin+$ann_height);
}

=head1 NAME

annotate_change_bars.pl - analyze PDF file with change bars, annotate navigation links along bottom

=head1 SYNOPSIS

  <pdf_filename>
          PDF file to process
  [--output <new_file_name>]
          Output PDF file to create
          (default is to modify original file in-place)

=head1 VERSION

0.60

=cut

