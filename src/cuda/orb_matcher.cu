/**
* This file is part of Jetson-SLAM.
*
* Written by Ashish Kumar Indian Institute of Tehcnology, Kanpur, India
* For more information see <https://github.com/ashishkumar822/Jetson-SLAM>
*
* Jetson-SLAM is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* Jetson-SLAM is distributed WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
* GNU General Public License for more details.
*
*/

//// Part of the Middle-end

#include "cuda/orb_matcher.hpp"

#include<cuda.h>
#include<cuda_device_runtime_api.h>
#include<cuda_runtime_api.h>

#include<stdio.h>

#include<iostream>

#include<chrono>

namespace orb_cuda{

#define CUDA_NUM_THREADS_PER_BLOCK 512

__global__ void ORB_Search_by_projection_project_on_GPU(int n_threads,
                                                        float* Px, float* Py, float* Pz,
                                                        float* Rcw, float* tcw,
                                                        float fx, float fy, float cx, float cy,
                                                        float minX, float maxX, float minY, float maxY,
                                                        float* u, float* v, float* invz,
                                                        unsigned char* is_valid)
{

    int index = blockIdx.x * blockDim.x + threadIdx.x;

    if(index <  n_threads)
    {
        unsigned char isvalid = 0;

        const float Pwx = Px[index];
        const float Pwy = Py[index];
        const float Pwz = Pz[index];

        const float Pcx = Pwx * Rcw[0] + Pwy * Rcw[1] + Pwz * Rcw[2] + tcw[0];
        const float Pcy = Pwx * Rcw[3] + Pwy * Rcw[4] + Pwz * Rcw[5] + tcw[1];
        const float Pcz = Pwx * Rcw[6] + Pwy * Rcw[7] + Pwz * Rcw[8] + tcw[2];

        float im_invz = -1;
        float im_u = -1;
        float im_v = -1;

        // Check positive depth
        if(Pcz > 0.0f)
        {
            // Project in image and check it is not outside
            im_invz = 1.0f / Pcz;
            im_u = fx * Pcx * im_invz + cx;
            im_v = fy * Pcy * im_invz + cy;

            if(!(im_u < minX || im_u > maxX || im_v < minY || im_v > maxY))
                isvalid = 1;

        }

        u[index] = im_u;
        v[index] = im_v;
        invz[index] = im_invz;
        is_valid[index] = isvalid;
    }
}


void ORB_Search_by_projection_project_on_frame(int n_points,
                                               float* Px_gpu, float* Py_gpu, float* Pz_gpu,
                                               float* Rcw_gpu, float* tcw_gpu,
                                               float& fx, float& fy, float& cx, float& cy,
                                               float& minX, float& maxX, float& minY, float& maxY,
                                               float* u_gpu, float* v_gpu, float* invz_gpu,
                                               unsigned char* is_valid_gpu)
{

    int n_threads = n_points;

    int CUDA_NUM_BLOCKS = (n_threads + CUDA_NUM_THREADS_PER_BLOCK) / CUDA_NUM_THREADS_PER_BLOCK;

    ORB_Search_by_projection_project_on_GPU<<<CUDA_NUM_BLOCKS, CUDA_NUM_THREADS_PER_BLOCK>>>(
                                                                                               n_threads,
                                                                                               Px_gpu, Py_gpu, Pz_gpu,
                                                                                               Rcw_gpu, tcw_gpu,
                                                                                               fx, fy, cx, cy,
                                                                                               minX, maxX, minY, maxY,
                                                                                               u_gpu,  v_gpu, invz_gpu,
                                                                                               is_valid_gpu
                                                                                               );

    cudaStreamSynchronize(0);
}





__global__ void ORB_compute_descriptor_Distance_GPU(int n_threads,
                                                    int* idx_left, int* idx_right,
                                                    unsigned char*  descriptor_left,
                                                    unsigned char*  descriptor_right,
                                                    int* distance)
{
    int index = blockIdx.x * blockDim.x + threadIdx.x;

    if(index <  n_threads)
    {
        int* d_left  = (int*)(descriptor_left  + idx_left[index] * 32);
        int* d_right = (int*)(descriptor_right + idx_right[index] * 32);

        int dist=0;

        for(int i=0; i<8; i++)
        {
            unsigned  int v = d_left[i] ^ d_right[i];
            v = v - ((v >> 1) & 0x55555555);
            v = (v & 0x33333333) + ((v >> 2) & 0x33333333);
            dist += (((v + (v >> 4)) & 0xF0F0F0F) * 0x1010101) >> 24;
        }

        distance[index] = dist;
    }
}


void ORB_compute_distances(int n_points,
                           int* idx_left, int* idx_right,
                           unsigned char*  descriptor_left,
                           unsigned char*  descriptor_right,
                           int* distance)
{
    int n_threads =  n_points;

    int CUDA_NUM_BLOCKS = (n_threads + CUDA_NUM_THREADS_PER_BLOCK) / CUDA_NUM_THREADS_PER_BLOCK;

    ORB_compute_descriptor_Distance_GPU<<<CUDA_NUM_BLOCKS, CUDA_NUM_THREADS_PER_BLOCK>>>(
                                                                                           n_threads,
                                                                                           idx_left, idx_right,
                                                                                           descriptor_left,
                                                                                           descriptor_right,
                                                                                           distance
                                                                                           );


    cudaStreamSynchronize(0);

//    std::cout << "line " << __LINE__ << " curror =  " << cudaGetLastError() << "\n";

}

}

