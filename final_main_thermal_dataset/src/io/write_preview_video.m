function write_preview_video(frame_dir, out_path, fps, is_color)
    files = dir(fullfile(frame_dir, 'frame*.png'));
    files = {files.name};
    files = sort(files);

    vw = VideoWriter(out_path, 'MPEG-4');
    vw.FrameRate = fps;
    open(vw);

    for k = 1:numel(files)
        img = imread(fullfile(frame_dir, files{k}));
        if is_color
            frame8 = img;
        else
            frame8 = uint8(double(img) / 65535 * 255);
            frame8 = repmat(frame8, [1 1 3]);
        end
        writeVideo(vw, frame8);
    end
    close(vw);
end
