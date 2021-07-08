#ifndef TACO_LG_CU_LEAF_KERNELS_H
#define TACO_LG_CU_LEAF_KERNELS_H

#include "leaf_kernels.h"
#include "cudalibs.h"
#include "cublas_v2.h"

template <typename T>
__global__
void fillInter(size_t B1_dimension, size_t C1_dimension, size_t D2_dimension, T* inter){
  size_t inter1_dimension = B1_dimension;
  size_t inter2_dimension = C1_dimension;
  size_t inter3_dimension = D2_dimension;

  int32_t io = blockIdx.x;
  int32_t ii = (threadIdx.x % (256));
  if (threadIdx.x >= 256) {
    return;
  }

  int32_t f = (io * 256 + ii);
  int32_t i = f / (inter2_dimension);
  int32_t iinter = 0 * inter1_dimension + i;
  if (i >= inter1_dimension)
    return;

  int32_t j = f % (inter2_dimension);
  int32_t jinter = iinter * inter2_dimension + j;
  if (j >= inter2_dimension)
    return;

  int32_t iinter = 0 * inter1_dimension + i;
  int32_t jinter = iinter * inter2_dimension + j;
  int32_t jinter = iinter * inter2_dimension + j;
  for (int32_t l = 0; l < inter3_dimension; l++) {
    int32_t linter = jinter * inter3_dimension + l;
    inter[linter] = 0;
  }
}

template<typename T>
__global__
void contractInter(MTTKRPPack pack, T* A, const T* C, const T* inter){
  int A1_dimension = pack.iDim;
  int A2_dimension = pack.lDim;
  int C1_dimension = pack.jDim;
  int C2_dimension = pack.lDim;
  int inter1_dimension = pack.iDim;
  int inter2_dimension = pack.jDim;
  int inter3_dimension = pack.lDim;

  int32_t io = blockIdx.x;
  int32_t ii = (threadIdx.x % (256));
  if (threadIdx.x >= 256) {
    return;
  }

  int32_t f = (io * 256 + ii);
  int32_t i = f / (C1_dimension);
  int32_t iinter = 0 * inter1_dimension + i;
  int32_t iA = i;
  if (i >= inter1_dimension)
    return;

  int32_t j = f % (C1_dimension);
  int32_t jinter = iinter * inter2_dimension + j;
  int32_t jC = j;
  if (j >= C1_dimension)
    return;

  int32_t iA = i;
  int32_t jinter = iinter * inter2_dimension + j;
  int32_t jC = j;
  for (int32_t l = 0; l < C2_dimension; l++) {
    int32_t lA = iA * pack.ldA + l;
    int32_t linter = jinter * inter3_dimension + l;
    int32_t lC = jC * pack.ldC + l;
    atomicAdd(&A[lA], inter[linter] * C[lC]);
  }
}

// CUDA version of mttkrp. All buffers must live on memory accessible by the device.
template <typename T>
void cu_mttkrp(MTTKRPPack pack, T* A_vals, const T* B_vals, const T* C_vals, const T* D_vals) {
  size_t B1_dimension = pack.iDim;
  size_t C1_dimension = pack.jDim;
  size_t D1_dimension = pack.kDim;
  size_t D2_dimension = pack.lDim;
  int ldA = pack.ldA;
  int ldC = pack.ldC;
  int ldD = pack.ldD;
  int ldB1 = pack.ldB1;
  int ldB2 = pack.ldB2;
  int ldB3 = pack.ldB3;

  double alpha = 1.0000000000000000;
  cublasHandle_t handle = getCuBLAS();
  cudaStream_t taskStream = cudaStream_t();
  cudaStreamCreate(&(taskStream));
  CHECK_CUBLAS(cublasSetStream(handle, taskStream));

  // Allocate an intermediate result T(i, j, l).
  double* inter;
  // TODO (rohany): Add an error check.
  cudaMalloc(&inter, B1_dimension * C1_dimension * D2_dimension * sizeof(T));
  fillInter<<<(B1_dimension * C1_dimension + 255) / 256, 256, 0, taskStream>>>(B1_dimension, C1_dimension, D2_dimension, inter);

  // Perform T(i, j, l) = B(i, j, k) * D(k, l) as a series of GEMM calls.
  for (size_t i = 0; i < B1_dimension; i++) {
    CHECK_CUBLAS(cublasDgemm(
        handle,
        CUBLAS_OP_N,
        CUBLAS_OP_N,
        D2_dimension,
        C1_dimension,
        D1_dimension,
        &alpha,
        D_vals,
        ldD,
        B_vals + (ldB1 * i),
        ldB3,
        &alpha,
        inter + (C1_dimension * D2_dimension * i),
        D2_dimension
    ));
  }

  // Perform the next reduction A(i, l) = T(i, j, l) * D(j, l).
  contractInter<<<(B1_dimension * C1_dimension + 255) / 256, 256, 0, taskStream>>>(pack, A, C, inter);

  // Clean up after ourselves.
  // TODO (rohany): Add an error check.
  cudaFree(inter);
}

#endif // TACO_LG_CU_LEAF_KERNELS_H