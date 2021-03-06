#include "cupoch/geometry/trianglemesh.h"
#include "cupoch/utility/console.h"

using namespace cupoch;
using namespace cupoch::geometry;

namespace {

struct compute_sphere_vertices_functor {
    compute_sphere_vertices_functor(int resolution, float radius)
        : resolution_(resolution), radius_(radius) {step_ = M_PI / (float)resolution;};
    const int resolution_;
    const float radius_;
    float step_;
    __device__
    Eigen::Vector3f operator() (size_t idx) const {
        int i = idx / (2 * resolution_) + 1;
        int j = idx % (2 * resolution_);

        float alpha = step_ * i;
        float theta = step_ * j;
        return Eigen::Vector3f(sin(alpha) * cos(theta),
                               sin(alpha) * sin(theta),
                               cos(alpha)) * radius_;
    }
};

struct compute_sphere_triangles_functor1 {
    compute_sphere_triangles_functor1(Eigen::Vector3i* triangle, int resolution)
        : triangles_(triangle), resolution_(resolution) {};
    Eigen::Vector3i* triangles_;
    const int resolution_;
    __device__
    void operator() (size_t idx) {
        int j1 = (idx + 1) % (2 * resolution_);
        int base = 2;
        triangles_[2 * idx] = Eigen::Vector3i(0, base + idx, base + j1);
        base = 2 + 2 * resolution_ * (resolution_ - 2);
        triangles_[2 * idx + 1] = Eigen::Vector3i(1, base + j1, base + idx);
    }
};

struct compute_sphere_triangles_functor2 {
    compute_sphere_triangles_functor2(Eigen::Vector3i* triangle, int resolution)
        : triangles_(triangle), resolution_(resolution) {};
    Eigen::Vector3i* triangles_;
    const int resolution_;
    __device__
    void operator() (size_t idx) {
        int i = idx / (2 * resolution_) + 1;
        int j = idx % (2 * resolution_);
        int base1 = 2 + 2 * resolution_ * (i - 1);
        int base2 = base1 + 2 * resolution_;
        int j1 = (j + 1) % (2 * resolution_);
        triangles_[2 * idx] = Eigen::Vector3i(base2 + j, base1 + j1, base1 + j);
        triangles_[2 * idx + 1] = Eigen::Vector3i(base2 + j, base2 + j1, base1 + j1);
    }
};

struct compute_cylinder_vertices_functor {
    compute_cylinder_vertices_functor(int resolution, float radius, float height, float step, float h_step)
        : resolution_(resolution), radius_(radius), height_(height), step_(step), h_step_(h_step) {};
    const int resolution_;
    const float radius_;
    const float height_;
    const float step_;
    const float h_step_;
    __device__
    Eigen::Vector3f operator() (size_t idx) const {
        int i = idx / resolution_;
        int j = idx % resolution_;
        float theta = step_ * j;
        return Eigen::Vector3f(cos(theta) * radius_, sin(theta) * radius_,
                               height_ * 0.5 - h_step_ * i);
    }
};

struct compute_cylinder_triangles_functor1 {
    compute_cylinder_triangles_functor1(Eigen::Vector3i* triangle, int resolution, int split)
        : triangles_(triangle), resolution_(resolution), split_(split) {};
    Eigen::Vector3i* triangles_;
    const int resolution_;
    const int split_;
    __device__
    void operator() (size_t idx) {
        int j1 = (idx + 1) % resolution_;
        int base = 2;
        triangles_[2 * idx] = Eigen::Vector3i(0, base + idx, base + j1);
        base = 2 + resolution_ * split_;
        triangles_[2 * idx + 1] = Eigen::Vector3i(1, base + j1, base + idx);
    }
};

struct compute_cylinder_triangles_functor2 {
    compute_cylinder_triangles_functor2(Eigen::Vector3i* triangle, int resolution)
        : triangles_(triangle), resolution_(resolution) {};
    Eigen::Vector3i* triangles_;
    const int resolution_;
    __device__
    void operator() (size_t idx) {
        int i = idx / resolution_;
        int j = idx % resolution_;
        int base1 = 2 + resolution_ * i;
        int base2 = base1 + resolution_;
        int j1 = (j + 1) % resolution_;
        triangles_[2 * idx] = Eigen::Vector3i(base2 + j, base1 + j1, base1 + j);
        triangles_[2 * idx + 1] = Eigen::Vector3i(base2 + j, base2 + j1, base1 + j1);
    }
};

struct compute_cone_vertices_functor {
    compute_cone_vertices_functor(int resolution, int split, float step, float r_step, float h_step)
        : resolution_(resolution), split_(split), step_(step), r_step_(r_step), h_step_(h_step) {};
    const int resolution_;
    const int split_;
    const float step_;
    const float r_step_;
    const float h_step_;
    __device__
    Eigen::Vector3f operator() (size_t idx) const {
        int i = idx / resolution_;
        int j = idx % resolution_;
        float r = r_step_ * (split_ - i);
        float theta = step_ * j;
        return Eigen::Vector3f(cos(theta) * r, sin(theta) * r, h_step_ * i);
     }
};

struct compute_cone_triangles_functor1 {
    compute_cone_triangles_functor1(Eigen::Vector3i* triangle, int resolution, int split)
        : triangles_(triangle), resolution_(resolution), split_(split) {};
    Eigen::Vector3i* triangles_;
    const int resolution_;
    const int split_;
    __device__
    void operator() (size_t idx) {
        int j1 = (idx + 1) % resolution_;
        int base = 2;
        triangles_[2 * idx] = Eigen::Vector3i(0, base + j1, base + idx);
        base = 2 + resolution_ * (split_ - 1);
        triangles_[2 * idx + 1] = Eigen::Vector3i(1, base + idx, base + j1);
    }
};

struct compute_cone_triangles_functor2 {
    compute_cone_triangles_functor2(Eigen::Vector3i* triangle, int resolution)
        : triangles_(triangle), resolution_(resolution) {};
    Eigen::Vector3i* triangles_;
    const int resolution_;
    __device__
    void operator() (size_t idx) {
        int i = idx / resolution_;
        int j = idx % resolution_;
        int base1 = 2 + resolution_ * i;
        int base2 = base1 + resolution_;
        int j1 = (j + 1) % resolution_;
        triangles_[2 * idx] = Eigen::Vector3i(base2 + j1, base1 + j, base1 + j1);
        triangles_[2 * idx + 1] = Eigen::Vector3i(base2 + j1, base2 + j, base1 + j);
    }
};

}

std::shared_ptr<TriangleMesh> TriangleMesh::CreateSphere(
        float radius /* = 1.0*/, int resolution /* = 20*/) {
    auto mesh_ptr = std::make_shared<TriangleMesh>();
    if (radius <= 0) {
        utility::LogError("[CreateSphere] radius <= 0");
    }
    if (resolution <= 0) {
        utility::LogError("[CreateSphere] resolution <= 0");
    }
    size_t n_vertices = 2 * resolution * (resolution - 1) + 2;
    mesh_ptr->vertices_.resize(n_vertices);
    mesh_ptr->vertices_[0] = Eigen::Vector3f(0.0, 0.0, radius);
    mesh_ptr->vertices_[1] = Eigen::Vector3f(0.0, 0.0, -radius);
    compute_sphere_vertices_functor func_vt(resolution, radius);
    thrust::transform(thrust::make_counting_iterator<size_t>(0),
                      thrust::make_counting_iterator(n_vertices - 2),
                      mesh_ptr->vertices_.begin() + 2, func_vt);
    mesh_ptr->triangles_.resize(2 * resolution + 4 * (resolution - 2) * resolution);
    compute_sphere_triangles_functor1 func_tr1(thrust::raw_pointer_cast(mesh_ptr->triangles_.data()), resolution);
    thrust::for_each(thrust::make_counting_iterator<size_t>(0),
                     thrust::make_counting_iterator<size_t>(2 * resolution), func_tr1);
    compute_sphere_triangles_functor2 func_tr2(thrust::raw_pointer_cast(mesh_ptr->triangles_.data()) + 2 * resolution,
                                               resolution);
    thrust::for_each(thrust::make_counting_iterator<size_t>(0),
                     thrust::make_counting_iterator<size_t>(2 * (resolution - 1) * resolution), func_tr2);
    return mesh_ptr;
}

std::shared_ptr<TriangleMesh> TriangleMesh::CreateCylinder(
        float radius /* = 1.0*/,
        float height /* = 2.0*/,
        int resolution /* = 20*/,
        int split /* = 4*/) {
    auto mesh_ptr = std::make_shared<TriangleMesh>();
    if (radius <= 0) {
        utility::LogError("[CreateCylinder] radius <= 0");
    }
    if (height <= 0) {
        utility::LogError("[CreateCylinder] height <= 0");
    }
    if (resolution <= 0) {
        utility::LogError("[CreateCylinder] resolution <= 0");
    }
    if (split <= 0) {
        utility::LogError("[CreateCylinder] split <= 0");
    }
    size_t n_vertices = resolution * (split + 1) + 2;
    mesh_ptr->vertices_.resize(n_vertices);
    mesh_ptr->vertices_[0] = Eigen::Vector3f(0.0, 0.0, height * 0.5);
    mesh_ptr->vertices_[1] = Eigen::Vector3f(0.0, 0.0, -height * 0.5);
    float step = M_PI * 2.0 / (float)resolution;
    float h_step = height / (float)split;
    compute_cylinder_vertices_functor func_vt(resolution, radius, height, step, h_step);
    thrust::transform(thrust::make_counting_iterator<size_t>(0),
                      thrust::make_counting_iterator<size_t>(n_vertices - 2),
                      mesh_ptr->vertices_.begin() + 2, func_vt);
    mesh_ptr->triangles_.resize(resolution + split * resolution);
    compute_cylinder_triangles_functor1 func_tr1(thrust::raw_pointer_cast(mesh_ptr->triangles_.data()), resolution, split);
    for_each(thrust::make_counting_iterator<size_t>(0), thrust::make_counting_iterator<size_t>(resolution), func_tr1);
    compute_cylinder_triangles_functor2 func_tr2(thrust::raw_pointer_cast(mesh_ptr->triangles_.data()) + resolution, resolution);
    for_each(thrust::make_counting_iterator<size_t>(0), thrust::make_counting_iterator<size_t>(resolution * split), func_tr2);
    return mesh_ptr;
}

std::shared_ptr<TriangleMesh> TriangleMesh::CreateCone(float radius /* = 1.0*/,
                                                       float height /* = 2.0*/,
                                                       int resolution /* = 20*/,
                                                       int split /* = 4*/) {
    auto mesh_ptr = std::make_shared<TriangleMesh>();
    if (radius <= 0) {
        utility::LogError("[CreateCone] radius <= 0");
    }
    if (height <= 0) {
        utility::LogError("[CreateCone] height <= 0");
    }
    if (resolution <= 0) {
        utility::LogError("[CreateCone] resolution <= 0");
    }
    if (split <= 0) {
        utility::LogError("[CreateCone] split <= 0");
    }
    mesh_ptr->vertices_.resize(resolution * split + 2);
    mesh_ptr->vertices_[0] = Eigen::Vector3f(0.0, 0.0, 0.0);
    mesh_ptr->vertices_[1] = Eigen::Vector3f(0.0, 0.0, height);
    float step = M_PI * 2.0 / (float)resolution;
    float h_step = height / (float)split;
    float r_step = radius / (float)split;
    compute_cone_vertices_functor func_vt(resolution, split, step, r_step, h_step);
    thrust::transform(thrust::make_counting_iterator<size_t>(0), thrust::make_counting_iterator<size_t>(resolution * split),
                      mesh_ptr->vertices_.begin() + 2, func_vt);
    mesh_ptr->triangles_.resize(resolution + (split - 1) * resolution);
    compute_cone_triangles_functor1 func_tr1(thrust::raw_pointer_cast(mesh_ptr->triangles_.data()), resolution, split);
    thrust::for_each(thrust::make_counting_iterator<size_t>(0), thrust::make_counting_iterator<size_t>(resolution), func_tr1);
    compute_cone_triangles_functor2 func_tr2(thrust::raw_pointer_cast(mesh_ptr->triangles_.data()) + resolution,
                                             resolution);
    thrust::for_each(thrust::make_counting_iterator<size_t>(0),
                     thrust::make_counting_iterator<size_t>((split - 1) * resolution), func_tr2);
    return mesh_ptr;
}

std::shared_ptr<TriangleMesh> TriangleMesh::CreateArrow(
        float cylinder_radius /* = 1.0*/,
        float cone_radius /* = 1.5*/,
        float cylinder_height /* = 5.0*/,
        float cone_height /* = 4.0*/,
        int resolution /* = 20*/,
        int cylinder_split /* = 4*/,
        int cone_split /* = 1*/) {
    if (cylinder_radius <= 0) {
        utility::LogError("[CreateArrow] cylinder_radius <= 0");
    }
    if (cone_radius <= 0) {
        utility::LogError("[CreateArrow] cone_radius <= 0");
    }
    if (cylinder_height <= 0) {
        utility::LogError("[CreateArrow] cylinder_height <= 0");
    }
    if (cone_height <= 0) {
        utility::LogError("[CreateArrow] cone_height <= 0");
    }
    if (resolution <= 0) {
        utility::LogError("[CreateArrow] resolution <= 0");
    }
    if (cylinder_split <= 0) {
        utility::LogError("[CreateArrow] cylinder_split <= 0");
    }
    if (cone_split <= 0) {
        utility::LogError("[CreateArrow] cone_split <= 0");
    }
    Eigen::Matrix4f transformation = Eigen::Matrix4f::Identity();
    auto mesh_cylinder = CreateCylinder(cylinder_radius, cylinder_height,
                                        resolution, cylinder_split);
    transformation(2, 3) = cylinder_height * 0.5;
    mesh_cylinder->Transform(transformation);
    auto mesh_cone =
            CreateCone(cone_radius, cone_height, resolution, cone_split);
    transformation(2, 3) = cylinder_height;
    mesh_cone->Transform(transformation);
    auto mesh_arrow = mesh_cylinder;
    *mesh_arrow += *mesh_cone;
    return mesh_arrow;
}

std::shared_ptr<TriangleMesh> TriangleMesh::CreateCoordinateFrame(
        float size /* = 1.0*/,
        const Eigen::Vector3f &origin /* = Eigen::Vector3f(0.0, 0.0, 0.0)*/) {
    if (size <= 0) {
        utility::LogError("[CreateCoordinateFrame] size <= 0");
    }
    auto mesh_frame = CreateSphere(0.06 * size);
    mesh_frame->ComputeVertexNormals();
    mesh_frame->PaintUniformColor(Eigen::Vector3f(0.5, 0.5, 0.5));

    std::shared_ptr<TriangleMesh> mesh_arrow;
    Eigen::Matrix4f transformation;

    mesh_arrow = CreateArrow(0.035 * size, 0.06 * size, 0.8 * size, 0.2 * size);
    mesh_arrow->ComputeVertexNormals();
    mesh_arrow->PaintUniformColor(Eigen::Vector3f(1.0, 0.0, 0.0));
    transformation << 0, 0, 1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1;
    mesh_arrow->Transform(transformation);
    *mesh_frame += *mesh_arrow;

    mesh_arrow = CreateArrow(0.035 * size, 0.06 * size, 0.8 * size, 0.2 * size);
    mesh_arrow->ComputeVertexNormals();
    mesh_arrow->PaintUniformColor(Eigen::Vector3f(0.0, 1.0, 0.0));
    transformation << 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 1;
    mesh_arrow->Transform(transformation);
    *mesh_frame += *mesh_arrow;

    mesh_arrow = CreateArrow(0.035 * size, 0.06 * size, 0.8 * size, 0.2 * size);
    mesh_arrow->ComputeVertexNormals();
    mesh_arrow->PaintUniformColor(Eigen::Vector3f(0.0, 0.0, 1.0));
    transformation << 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1;
    mesh_arrow->Transform(transformation);
    *mesh_frame += *mesh_arrow;

    transformation = Eigen::Matrix4f::Identity();
    transformation.block<3, 1>(0, 3) = origin;
    mesh_frame->Transform(transformation);

    return mesh_frame;
}