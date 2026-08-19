
function projection = project_to_camera( ...
                        target,...
                        chief_pos_eci,...
                        chief_quat,...
                        deputy_pos_eci,...
                        deputy_quat,...
                        config)

R_eci_to_body = quat2rotm(deputy_quat);

los = chief_pos_eci - deputy_pos_eci;
los = los / norm(los);

disp('LOS in BODY frame')
disp(R_eci_to_body * los)

R_body_to_eci_chief = ...
    quat2rotm(chief_quat);

f = config.thermal.focal_length;

pixel_pitch = ...
    config.thermal.pixel_pitch;

img_w = ...
    config.thermal.resolution(1);

img_h = ...
    config.thermal.resolution(2);

range = norm( ...
    chief_pos_eci - ...
    deputy_pos_eci);

R_body_to_eci_chief = ...
    quat2rotm(chief_quat);

roll = deg2rad( ...
    config.thermal.mount_roll_deg);

pitch = deg2rad( ...
    config.thermal.mount_pitch_deg);

yaw = deg2rad( ...
    config.thermal.mount_yaw_deg);

Rx = [ ...
    1 0 0;
    0 cos(roll) -sin(roll);
    0 sin(roll)  cos(roll)];

Ry = [ ...
     cos(pitch) 0 sin(pitch);
     0          1 0;
    -sin(pitch) 0 cos(pitch)];

Rz = [ ...
    cos(yaw) -sin(yaw) 0;
    sin(yaw)  cos(yaw) 0;
    0         0        1];

R_body_to_thermal = ...
    Rz * Ry * Rx;

R_eci_to_thermal = ...
    R_body_to_thermal * ...
    R_eci_to_body;

N = size(target.vertices,1);

vertices_thermal = ...
    zeros(N,3);

for k = 1:N

   vertex_body = ...
    target.vertices(k,:)';

    vertex_eci = ...
    chief_pos_eci + ...
    R_body_to_eci_chief * vertex_body;

    vertex_thermal = ...
        R_eci_to_thermal * ...
        (vertex_eci - deputy_pos_eci);

    vertices_thermal(k,:) = ...
        vertex_thermal';

end

pixel_uv = nan(N,2);

for k = 1:N

    X = vertices_thermal(k,1);
    Y = vertices_thermal(k,2);
    Z = vertices_thermal(k,3);

    if Z <= 0.01
        continue
    end

    u = f * X / Z;
    v = f * Y / Z;

    px = ...
        u/pixel_pitch + img_w/2;

    py = ...
        v/pixel_pitch + img_h/2;

    pixel_uv(k,:) = ...
        [px py];

end

projection.vertices_thermal = ...
    vertices_thermal;

projection.pixel_uv = ...
    pixel_uv;

projection.range = ...
    range;

projection.R_eci_to_thermal = ...
    R_eci_to_thermal;

end
