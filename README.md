# pdf-annotate-change-bars
Analyzes a PDF file with change bars, then adds clickable links to step through the changed pages

# Introduction
In our technical publications flow, we save PDF files with change bars, then give those files to reviewers to comment on the changes. However, for large (1000+ page) documents, it was painful for the reviewers to search for the next set of change bars.

This perl script analyzes a PDF file for change bars, then adds navigation links along the bottom to jump to the next page with change bars. As you click anywhere within the bottom bar annotation, the viewer will jump to the next change-bar page.

![example annotated PDF](https://github.com/chrispy-snps/pdf-annotate-change-bars/blob/master/example.gif)

# Prerequisites

This perl script runs in linux. If you're running Windows 10, it also runs on Windows Subsystem for Linux (WSL).

You'll need the following packages:

    sudo apt update
    sudo apt install ghostscript imagemagick poppler-utils

Your PDFs must have a solid background color where the change bars are.

# Operation

The utility works as follows:

1. Renders a multipage low-res TIFF file from the PDF. (ghostscript)
2. Crops the TIFF images to a bounding box where the change bar exists. (pdfinfo, ImageMagick)
3. Performs a "background removal" operation to shrink each page image to just the change bar (if it exists) *or* to zero size (if none exists). (ImageMagick)
4. Uses the image sizes to determine which pages had change bars. (annotate_change_bars.pl)
5. Processes the PDF file to add clickable navigation links at the bottom. (ghostscript)

# Usage

First, edit the script to describe the bounding box where the change bars can exist:

    # define the change bar bounding box, in inches, from the upper-left corner
    my $x1 = 0.500;
    my $x2 = 0.875;
    my $y1 = 1.0;
    my $y2 = 10.0;

Any content in this bounding box - even headers or footers - will be treated as a change bar.

Next, run the utility on your PDF file as follows:

    annotate_change_bars.pl my_file.pdf [-o new_file.pdf]

If you do not specify the `-o` option, the file is modified in-place with the annotated file.

The script produces output as follows:

    Getting change bar information from PDF...
      Creating multipage TIFF image file for change bars...
      Getting change bar heights...
    convert-im6.q16: geometry does not contain image `/tmp/test_orig.tiff' @ warning/attribute.c/GetImageBoundingBox/247.
        Total changed pages detected: 5
          3 6 7 8 10
        Total change sections: 3
          3
          6 7 8
          10
    Creating annotated PDF file 'test_orig.pdf'...

(Any "geometry does not contain image" messages are harmless.)

# Known Limitations

Most in-browser PDF viewers do not render text in the navigation bar at the bottom. (Specifically, they do not render /FreeText pdfmark annotations.) However, the link is still clickable and navigation still works. Standalone PDF viewing programs generally work fine.
