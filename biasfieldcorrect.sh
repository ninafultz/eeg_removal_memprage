#!/usr/bin/python3
"""
Bias Field Correction via SPM.
Also ouputs the 5 segmented classes.

Currently only supports nii and nii.gz inputs.

Daniel Gomez 2021.03.25 -- initial version
Daniel Gomez 2021.05.08 -- add support for segmentation classes.
"""
import argparse
import os
import os.path as op
import string
import gzip
import tempfile
import subprocess


# SPM bias field correction first segments the brain generating 5 segmentation
# classes, as listed below. The values c1-c5 represent prefixes that are
# prepended to the input filename by SPM.
spm_segmentation_classes: {
    "GM": "c1",
    "WM": "c2",
    "CSF": "c3",
    "bone": "c4",
    "other": "c5",
}


bfc_script = string.Template(
    """
    matlabbatch{1}.spm.spatial.preproc.channel.vols = {'$INPUTDATA,1'};
    matlabbatch{1}.spm.spatial.preproc.channel.biasreg = 0.001;
    matlabbatch{1}.spm.spatial.preproc.channel.biasfwhm = 20;
    matlabbatch{1}.spm.spatial.preproc.channel.write = [1 1];
    matlabbatch{1}.spm.spatial.preproc.warp.mrf = 1;
    matlabbatch{1}.spm.spatial.preproc.warp.cleanup = 1;
    matlabbatch{1}.spm.spatial.preproc.warp.reg = [0 0.001 0.5 0.05 0.2];
    matlabbatch{1}.spm.spatial.preproc.warp.affreg = 'mni';
    matlabbatch{1}.spm.spatial.preproc.warp.fwhm = 0;
    matlabbatch{1}.spm.spatial.preproc.warp.samp = 3;
    matlabbatch{1}.spm.spatial.preproc.warp.write = [0 0];

    spm('defaults','FMRI')
    spm_jobman('initcfg');
    spm_jobman('run',matlabbatch);

    exit
    """
)


def cli_parser():

    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("infile", help="Name of input file to be corrected")
    parser.add_argument("outfile", help="Name of output bias field corrected file")
    parser.add_argument(
        "--with-segmentation",
        action="store_true",
        help="Also output probability masks of GM, WM, CSF, bone and other.",
    )
    return parser


def is_zipped(file):
    with gzip.open(file, "r") as fh:
        try:
            fh.read(1)
            return True
        except OSError:
            return False


def unzip(file):
    "Create a temporary unzipped version of a given file."
    os_filehandle, target = tempfile.mkstemp(suffix=".nii")
    with gzip.open(file, "rb") as decompressed:
        with open(target, "wb") as unzipped:
            unzipped.write(decompressed.read())
    return target


def afni_conversion_cmd(inname, outname):
    "Outputs a string that calls AFNI to rename and convert files based on names and extensions."
    return (
        f"3dcalc -a {inname} -prefix {outname} -expr 'a' -datum short"
    )


if __name__ == "__main__":
    args = cli_parser().parse_args()

    # Sanity checks and input preparation
    if not op.exists(args.infile):
        raise FileNotFoundError("Input file does not exist or is not readable.")
    else:
        file = unzip(args.infile) if is_zipped(args.infile) else args.infile

    if op.exists(args.outfile):
        raise OSError("Output file already exists. Not going to overwrite.")

    # Create output directory if it does not exist yet.
    outdir = op.dirname(op.abspath(args.outfile))
    if not op.exists(outdir):
        os.makedirs(outdir)

    # Create a temporary spm batch script which we'll pass to spm.
    os_filehandle, bfc_script_file = tempfile.mkstemp(suffix=".m")
    with open(bfc_script_file, "w") as f:
        f.write(bfc_script.substitute({"INPUTDATA": op.abspath(file)}))

    # Call SPM via a standalone singularity container.
    # The -B flag binds the input and output directories so that the container
    # can read -and write to/from them.
    tmpdir = op.dirname(op.abspath(file))
    process = subprocess.Popen(
        f"singularity run -B {tmpdir} -B {outdir} /cluster/visuo/users/share/lib/spm.sif batch {bfc_script_file}",
        shell=True,
        stdout=subprocess.PIPE,
    )
    process.wait()  # Synchronous execution, as we don't want to fire the next process below until SPM ends.

    # Use afni to change the format from long to short, and to implicitly zip the spm output file.
    afniprocess = subprocess.Popen(
        afni_conversion_cmd(f"{op.dirname(file)}/m{op.basename(file)}", args.outfile),
        shell=True,
        stdout=subprocess.PIPE,
    )

    if args.with_segmentation:
        for segclass, prefix in spm_segmentation_classes.items():
            seg_outname = args.infile.replace(".nii", f"_{segclass}.nii")
            subprocess.Popen(
                afni_conversion_cmd(
                    f"{op.dirname(file)}/{prefix}{op.basename(file)}",
                    seg_outname,
                ),
                shell=True,
                stdout=subprocess.PIPE,
            )
