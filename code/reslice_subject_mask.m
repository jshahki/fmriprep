function reslice_subject_mask(subject_id, mask_input_dir, output_dir, reference_file)
% Reslices a single subject's mask to match the BOLD reference resolution

spm('Defaults','fMRI');
spm_jobman('initcfg');

% Input mask
mask_dir = fullfile(mask_input_dir, subject_id, 'func');
mask = dir(fullfile(mask_dir, '*_desc-brain_mask.nii.gz'));

if isempty(mask)
    fprintf('No mask found for subject %s\n', subject_id);
    return;
end

% Unzip the mask file if necessary
gz_mask_path = fullfile(mask(1).folder, mask(1).name);
[~, base_name] = fileparts(mask(1).name);
if endsWith(base_name, '.nii')
    base_name = base_name(1:end-4);  % remove '.nii'
end
unzipped_mask_path = fullfile(mask(1).folder, [base_name, '.nii']);

if ~isfile(unzipped_mask_path)
    gunzip(gz_mask_path, mask(1).folder);
end

% Output path
subject_out_dir = fullfile(output_dir, subject_id);
if ~exist(subject_out_dir, 'dir')
    mkdir(subject_out_dir);
end

% Reslice using nearest neighbor interpolation
flags = struct('which', 1, 'interp', 0, 'wrap', [0 0 0], 'mask', 0, 'mean', 0);
spm_reslice({reference_file, unzipped_mask_path}, flags);

% Move resliced file to output folder
[~, mask_filename] = fileparts(unzipped_mask_path);
resliced_mask_name = ['r' mask_filename '.nii'];
movefile(fullfile(mask(1).folder, resliced_mask_name), ...
         fullfile(subject_out_dir, ['r_' mask_filename '.nii']));

% Clean up temporary unzipped mask
if isfile(unzipped_mask_path)
    delete(unzipped_mask_path);
end
end

