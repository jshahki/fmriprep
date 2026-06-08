function run_nonmasked_tSNR_calculations(input_folder, output_folder)
% Compute tSNR for each subject and save maps + summary

if ~exist(output_folder, 'dir')
    mkdir(output_folder);
end

subject_dirs = dir(input_folder);
subject_dirs = subject_dirs([subject_dirs.isdir] & ~startsWith({subject_dirs.name}, '.'));

subject_tSNRs = [];
valid_subjects = {};
accumulated_tSNR_map = [];
num_subjects = 0;

for i = 1:length(subject_dirs)
    subject_name = subject_dirs(i).name;
    subject_path = fullfile(input_folder, subject_name);
    
    nii_files = dir(fullfile(subject_path, 'sr_sub*.nii'));
    if isempty(nii_files)
        fprintf('No sr_sub*.nii files found for subject %s\n', subject_name);
        continue;
    end

    [~, idx] = sort({nii_files.name});
    nii_files = nii_files(idx);

    first_file = fullfile(subject_path, nii_files(1).name);
    info = niftiinfo(first_file);
    vol_size = info.ImageSize;
    num_vols = length(nii_files);
    data_4D = zeros([vol_size, num_vols]);

    try
        for v = 1:num_vols
            vol = niftiread(fullfile(subject_path, nii_files(v).name));
            data_4D(:,:,:,v) = double(vol);
        end

        mean_data = mean(data_4D, 4);
        std_data = std(data_4D, 0, 4);
        std_data(std_data == 0) = NaN;
        tSNR_map = mean_data ./ std_data;

        subject_mean_tSNR = mean(tSNR_map(:), 'omitnan');

        if ~isnan(subject_mean_tSNR)
            subject_tSNRs(end+1) = subject_mean_tSNR;
            valid_subjects{end+1} = subject_name;

            % Save per-subject tSNR map
            subject_tSNR_file = fullfile(output_folder, sprintf('%s_tSNR_nonmasked.nii', subject_name));
            niftiwrite(single(tSNR_map), subject_tSNR_file, info, 'Compressed', true);

            if isempty(accumulated_tSNR_map)
                accumulated_tSNR_map = tSNR_map;
            else
                accumulated_tSNR_map = accumulated_tSNR_map + tSNR_map;
            end

            num_subjects = num_subjects + 1;
        end
    catch ME
        fprintf('Error processing subject %s: %s\n', subject_name, ME.message);
    end
end

% Save CSV summary
output_csv = fullfile(output_folder, 'tSNR_nonmasked_summary.csv');
tSNR_table = table(valid_subjects', subject_tSNRs', 'VariableNames', {'Subject', 'Average_tSNR_Nonmasked'});
writetable(tSNR_table, output_csv);

% Bar chart
figure;
hold on;

% Plot bar for group average tSNR
bar(1, mean(subject_tSNRs, 'omitnan'), 'FaceColor', [0.2 0.6 0.8]);

% Overlay individual tSNR values — vertically aligned
scatter(ones(size(subject_tSNRs)), subject_tSNRs, 40, 'r', 'filled');  % No jitter

% Plot formatting
ylabel('tSNR');
title('Subject Nonmasked tSNR Distribution');
xlim([0.5 1.5]);
xticks(1);
xticklabels({'All Subjects'});
grid on;
box on;
hold off;

% Save the figure
saveas(gcf, fullfile(output_folder, 'tSNR_Nonmasked_BarPlot.png'));
close;

% Save group tSNR
if num_subjects > 0
    group_avg_tSNR = accumulated_tSNR_map / num_subjects;
    group_tSNR_file = fullfile(output_folder, 'Group_Average_tSNR_Nonmasked.nii');
    niftiwrite(single(group_avg_tSNR), group_tSNR_file, info, 'Compressed', true);
end

fprintf('Nonmasked tSNR calculations complete. Results saved to: %s\n', output_folder);
end

