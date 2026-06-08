function smoothing_spm_batch(in_dir, out_dir, subject, kernel_size)
    try
        fprintf('Starting smoothing for %s\n', subject);

        scanprefix = 's';  % Output prefix for smoothed files

        % Get input files
        files = dir(fullfile(in_dir, 'r_sub-*.nii'));
        if isempty(files)
            error('No input files found in %s', in_dir);
        end

        scans = cell(length(files), 1);
        for i = 1:length(files)
            in_file = fullfile(in_dir, files(i).name);
            out_file = fullfile(out_dir, files(i).name);
            copyfile(in_file, out_file);  % Copy input file to output dir
            scans{i} = [out_file, ',1'];
        end

        % Build SPM batch
        matlabbatch{1}.spm.spatial.smooth.data = scans;
        matlabbatch{1}.spm.spatial.smooth.fwhm = kernel_size;
        matlabbatch{1}.spm.spatial.smooth.dtype = 0;
        matlabbatch{1}.spm.spatial.smooth.im = 0;
        matlabbatch{1}.spm.spatial.smooth.prefix = scanprefix;

        % Run SPM smoothing
        spm('Defaults','fMRI');
        spm_jobman('initcfg');
        spm_jobman('run', matlabbatch);

        fprintf('Smoothing complete for %s\n', subject);

        % Delete unsmoothed files from the output directory
        for i = 1:length(files)
            out_file = fullfile(out_dir, files(i).name);
            if exist(out_file, 'file')
                delete(out_file);
            end
        end

        fprintf('Deleted unsmoothed files for %s\n', subject);

    catch ME
        fprintf(2, 'Error during smoothing for %s:\n%s\n', subject, ME.message);
        rethrow(ME)
    end
end

