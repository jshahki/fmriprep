function run_masked_tSNR_calculations(input_dir, resliced_mask_dir, output_dir)
% Compute masked tSNR per subject using resliced masks

if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

subject_dirs = dir(input_dir);
subject_dirs = subject_dirs([subject_dirs.isdir] & ~startsWith({subject_dirs.name}, '.'));

subject_tSNRs = [];
valid_subjects = {};

for i = 1:length(subject_dirs)
    subject_name = subject_dirs(i).name;
    subject_path = fullfile(input_dir, subject_name);

    % BOLD input files
    nii_files = dir(fullfile(subject_path, 'sr_sub*.nii'));
    if isempty(nii_files)
        fprintf('No sr_sub*.nii files found for subject %s\n', subject_name);
        continue;
    end

    % Load resliced mask
    mask_path = fullfile(resliced_mask_dir, subject_name);
    if ~isfolder(mask_path)
        fprintf('No resliced mask directory for subject %s — skipping...\n', subject_name);
        continue;
    end

    mask_file = dir(fullfile(mask_path, 'r_*.nii'));
    if isempty(mask_file)
        fprintf('No resliced mask file for subject %s — skipping...\n', subject_name);
        continue;
    end

    try
        mask = niftiread(fullfile(mask_file.folder, mask_file.name));
        mask = logical(mask);

        % Load BOLD stack
        first_file = fullfile(subject_path, nii_files(1).name);
        info = niftiinfo(first_file);
        vol_size = info.ImageSize;
        num_vols = length(nii_files);
        data_4D = zeros([vol_size, num_vols]);

        [~, idx] = sort({nii_files.name});
        nii_files = nii_files(idx);

        for v = 1:num_vols
            vol = niftiread(fullfile(subject_path, nii_files(v).name));
            data_4D(:,:,:,v) = double(vol);
        end

        mean_data = mean(data_4D, 4);
        std_data = std(data_4D, 0, 4);
        std_data(std_data == 0) = NaN;
        tSNR_map = mean_data ./ std_data;
        tSNR_map(~mask) = 0;

        % Mean tSNR
        subject_mean_tSNR = mean(tSNR_map(mask), 'omitnan');

        if ~isnan(subject_mean_tSNR)
            subject_tSNRs(end+1) = subject_mean_tSNR;
            valid_subjects{end+1} = subject_name;

            output_file = fullfile(output_dir, sprintf('%s_tSNR_masked.nii.gz', subject_name));
            niftiwrite(single(tSNR_map), output_file, info, 'Compressed', true);
        end

    catch ME
        fprintf('Error processing subject %s: %s\n', subject_name, ME.message);
    end
end

% CSV summary
summary_csv = fullfile(output_dir, 'tSNR_masked_summary.csv');
tSNR_table = table(valid_subjects', subject_tSNRs', 'VariableNames', {'Subject', 'Average_tSNR_Masked'});
writetable(tSNR_table, summary_csv);

% Bar plot
figure;
hold on;
bar(1, mean(subject_tSNRs, 'omitnan'), 'FaceColor', [0.2 0.6 0.8]);
scatter(ones(size(subject_tSNRs)), subject_tSNRs, 40, 'r', 'filled');
ylabel('tSNR');
title('Subject Masked tSNR Distribution');
xlim([0.5 1.5]);
xticks(1);
xticklabels({'All Subjects'});
grid on;
box on;
hold off;
saveas(gcf, fullfile(output_dir, 'tSNR_Masked_BarPlot.png'));
close;

fprintf('Masked tSNR calculations complete. Results saved to: %s\n', output_dir);
end

