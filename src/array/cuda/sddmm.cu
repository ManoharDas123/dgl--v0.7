/*!
 *  Copyright (c) 2020 by Contributors
 * \file array/cuda/sddmm.cu
 * \brief SDDMM C APIs and definitions.
 */
#include <dgl/array.h>
#include "./sddmm.cuh"
#include "./functor.cuh"

namespace dgl {
namespace aten {

#define SWITCH_OP(op, Op, ...)                                      \
  do {                                                              \
    if ((op) == "add") {                                            \
      typedef cuda::binary::Add<DType> Op;                          \
      { __VA_ARGS__ }                                               \
    } else if ((op) == "sub") {                                     \
      typedef cuda::binary::Sub<DType> Op;                          \
      { __VA_ARGS__ }                                               \
    } else if ((op) == "mul") {                                     \
      typedef cuda::binary::Mul<DType> Op;                          \
      { __VA_ARGS__ }                                               \
    } else if ((op) == "div") {                                     \
      typedef cuda::binary::Div<DType> Op;                          \
      { __VA_ARGS__ }                                               \
    } else if ((op) == "copy_lhs") {                                \
      typedef cuda::binary::CopyLhs<DType> Op;                      \
      { __VA_ARGS__ }                                               \
    } else if ((op) == "copy_rhs") {                                \
      typedef cuda::binary::CopyRhs<DType> Op;                      \
      { __VA_ARGS__ }                                               \
    } else if ((op) == "dot") {                                     \
      typedef cuda::binary::Dot<DType> Op;                          \
      { __VA_ARGS__ }                                               \
    } else {                                                        \
      LOG(FATAL) << "Unsupported SpMM/SDDMM binary operator: " << op;     \
    }                                                               \
  } while (0)

#define SWITCH_RHS(rhs_target, RhsTarget, ...)                        \
  do {                                                                \
    if ((rhs_target) == 0) {                                          \
      constexpr int RhsTarget = 0;                                    \
      { __VA_ARGS__ }                                                 \
    } else if ((rhs_target) == 1) {                                   \
      constexpr int RhsTarget = 1;                                    \
      { __VA_ARGS__ }                                                 \
    } else if ((rhs_target) == 2) {                                   \
      constexpr int RhsTarget = 2;                                    \
      { __VA_ARGS__ }                                                 \
    } else {                                                          \
      LOG(INFO) << "Invalid rhs target: " << (rhs_target);            \
    }                                                                 \
  } while (0)

#define SWITCH_TARGET(lhs_target, rhs_target, LhsTarget, RhsTarget, ...)\
  do {                                                                  \
    if ((lhs_target) == 0) {                                            \
      constexpr int LhsTarget = 0;                                      \
      SWITCH_RHS(rhs_target, RhsTarget, __VA_ARGS__);                   \
    } else if ((lhs_target) == 1) {                                     \
      constexpr int LhsTarget = 1;                                      \
      SWITCH_RHS(rhs_target, RhsTarget, __VA_ARGS__);                   \
    } else if ((lhs_target) == 2) {                                     \
      constexpr int LhsTarget = 2;                                      \
      SWITCH_RHS(rhs_target, RhsTarget, __VA_ARGS__);                   \
    } else {                                                            \
      LOG(INFO) << "Invalid lhs target: " << (lhs_target);              \
    }                                                                   \
  } while (0)

/*!
 * \brief CUDA implementation of g-SDDMM on Csr format.
 */
template <int XPU, typename IdType, int bits>
void SDDMMCsr(const std::string& op,
              const BcastOff& bcast,
              const CSRMatrix& csr,
              NDArray lhs,
              NDArray rhs,
              NDArray out,
              int lhs_target,
              int rhs_target) {
  SWITCH_BITS(bits, DType, {
    SWITCH_OP(op, Op, {
      SWITCH_TARGET(lhs_target, rhs_target, LhsTarget, RhsTarget, {
        cuda::SDDMMCsr<IdType, DType, Op, LhsTarget, RhsTarget>(bcast, csr, lhs, rhs, out);
      });
    });
  });
}

/*!
 * \brief CUDA implementation of g-SDDMM on heterograph using 
    Csr format.
 */
template <int XPU, typename IdType, int bits>
void SDDMMCsrHetero(const std::string& op,
              const BcastOff& bcast,
              const std::vector<CSRMatrix>& vec_csr,
              const std::vector<NDArray>& vec_lhs,
              const std::vector<NDArray>& vec_rhs,
              std::vector<NDArray> vec_out,
              int lhs_target,
              int rhs_target,
              const std::vector<dgl_type_t>& lhs_eid,
              const std::vector<dgl_type_t>& rhs_eid) {
  SWITCH_BITS(bits, DType, {
    SWITCH_OP(op, Op, {
      SWITCH_TARGET(lhs_target, rhs_target, LhsTarget, RhsTarget, {
        /* Call SDDMM CUDA kernel for each relation type sequentially */
        for (dgl_type_t etype = 0; etype < lhs_eid.size(); ++etype) {
          CSRMatrix csr = vec_csr[etype];
          NDArray lhs = vec_lhs[lhs_eid[etype]];
          NDArray rhs = vec_rhs[rhs_eid[etype]];
          NDArray out = vec_out[etype];
          cuda::SDDMMCsr<IdType, DType, Op, LhsTarget, RhsTarget>(
            bcast, csr, lhs, rhs, out);
        }
      });
    });
  });
}


/*!
 * \brief CUDA implementation of g-SDDMM on Coo format.
 */
template <int XPU, typename IdType, int bits>
void SDDMMCoo(const std::string& op,
              const BcastOff& bcast,
              const COOMatrix& coo,
              NDArray lhs,
              NDArray rhs,
              NDArray out,
              int lhs_target,
              int rhs_target) {
  SWITCH_BITS(bits, DType, {
    SWITCH_OP(op, Op, {
      SWITCH_TARGET(lhs_target, rhs_target, LhsTarget, RhsTarget, {
        cuda::SDDMMCoo<IdType, DType, Op, LhsTarget, RhsTarget>(bcast, coo, lhs, rhs, out);
      });
    });
  });
}


/*!
 * \brief CUDA implementation of g-SDDMM on heterograph using
    Csr format.
 */
template <int XPU, typename IdType, int bits>
void SDDMMCooHetero(const std::string& op,
              const BcastOff& bcast,
              const std::vector<COOMatrix>& vec_coo,
              const std::vector<NDArray>& vec_lhs,
              const std::vector<NDArray>& vec_rhs,
              std::vector<NDArray> vec_out,
              int lhs_target,
              int rhs_target,
              const std::vector<dgl_type_t>& lhs_eid,
              const std::vector<dgl_type_t>& rhs_eid) {
  auto* thr_entry = runtime::CUDAThreadEntry::ThreadLocal();
  SWITCH_BITS(bits, DType, {
    SWITCH_OP(op, Op, {
      SWITCH_TARGET(lhs_target, rhs_target, LhsTarget, RhsTarget, {
        /* Call SDDMM CUDA kernel for each relation type sequentially */
        for (dgl_type_t etype = 0; etype < lhs_eid.size(); ++etype) {
          COOMatrix coo = vec_coo[etype];
          NDArray lhs = vec_lhs[lhs_eid[etype]];
          NDArray rhs = vec_rhs[rhs_eid[etype]];
          NDArray out = vec_out[etype];
          cuda::SDDMMCoo<IdType, DType, Op, LhsTarget, RhsTarget>(
            bcast, coo, lhs, rhs, out);
        }
      });
    });
  });
}


template void SDDMMCsr<kDLGPU, int32_t, 16>(
    const std::string& op, const BcastOff& bcast, const CSRMatrix& csr,
    NDArray lhs, NDArray rhs, NDArray out,
    int lhs_target, int rhs_target);
template void SDDMMCsr<kDLGPU, int64_t, 16>(
    const std::string& op, const BcastOff& bcast, const CSRMatrix& csr,
    NDArray lhs, NDArray rhs, NDArray out,
    int lhs_target, int rhs_target);
template void SDDMMCsr<kDLGPU, int32_t, 32>(
    const std::string& op, const BcastOff& bcast, const CSRMatrix& csr,
    NDArray lhs, NDArray rhs, NDArray out,
    int lhs_target, int rhs_target);
template void SDDMMCsr<kDLGPU, int64_t, 32>(
    const std::string& op, const BcastOff& bcast, const CSRMatrix& csr,
    NDArray lhs, NDArray rhs, NDArray out,
    int lhs_target, int rhs_target);
template void SDDMMCsr<kDLGPU, int32_t, 64>(
    const std::string& op, const BcastOff& bcast, const CSRMatrix& csr,
    NDArray lhs, NDArray rhs, NDArray out,
    int lhs_target, int rhs_target);
template void SDDMMCsr<kDLGPU, int64_t, 64>(
    const std::string& op, const BcastOff& bcast, const CSRMatrix& csr,
    NDArray lhs, NDArray rhs, NDArray out,
    int lhs_target, int rhs_target);

template void SDDMMCsrHetero<kDLGPU, int32_t, 16>(
    const std::string& op, const BcastOff& bcast,
    const std::vector<CSRMatrix>& vec_csr,
    const std::vector<NDArray>& lhs, const std::vector<NDArray>& rhs,
    std::vector<NDArray> out, int lhs_target, int rhs_target,
    const std::vector<dgl_type_t>& in_eid,
    const std::vector<dgl_type_t>& out_eid);
template void SDDMMCsrHetero<kDLGPU, int64_t, 16>(
    const std::string& op, const BcastOff& bcast,
    const std::vector<CSRMatrix>& vec_csr,
    const std::vector<NDArray>& lhs, const std::vector<NDArray>& rhs,
    std::vector<NDArray> out, int lhs_target, int rhs_target,
    const std::vector<dgl_type_t>& in_eid,
    const std::vector<dgl_type_t>& out_eid);
template void SDDMMCsrHetero<kDLGPU, int32_t, 32>(
    const std::string& op, const BcastOff& bcast,
    const std::vector<CSRMatrix>& vec_csr,
    const std::vector<NDArray>& lhs, const std::vector<NDArray>& rhs,
    std::vector<NDArray> out, int lhs_target, int rhs_target,
    const std::vector<dgl_type_t>& in_eid,
    const std::vector<dgl_type_t>& out_eid);
template void SDDMMCsrHetero<kDLGPU, int64_t, 32>(
    const std::string& op, const BcastOff& bcast,
    const std::vector<CSRMatrix>& vec_csr,
    const std::vector<NDArray>& lhs, const std::vector<NDArray>& rhs,
    std::vector<NDArray> out, int lhs_target, int rhs_target,
    const std::vector<dgl_type_t>& in_eid,
    const std::vector<dgl_type_t>& out_eid);
template void SDDMMCsrHetero<kDLGPU, int32_t, 64>(
    const std::string& op, const BcastOff& bcast,
    const std::vector<CSRMatrix>& vec_csr,
    const std::vector<NDArray>& lhs, const std::vector<NDArray>& rhs,
    std::vector<NDArray> out, int lhs_target, int rhs_target,
    const std::vector<dgl_type_t>& in_eid,
    const std::vector<dgl_type_t>& out_eid);
template void SDDMMCsrHetero<kDLGPU, int64_t, 64>(
    const std::string& op, const BcastOff& bcast,
    const std::vector<CSRMatrix>& vec_csr,
    const std::vector<NDArray>& lhs, const std::vector<NDArray>& rhs,
    std::vector<NDArray> out, int lhs_target, int rhs_target,
    const std::vector<dgl_type_t>& in_eid,
    const std::vector<dgl_type_t>& out_eid);

template void SDDMMCoo<kDLGPU, int32_t, 16>(
    const std::string& op, const BcastOff& bcast, const COOMatrix& coo,
    NDArray lhs, NDArray rhs, NDArray out,
    int lhs_target, int rhs_target);
template void SDDMMCoo<kDLGPU, int64_t, 16>(
    const std::string& op, const BcastOff& bcast, const COOMatrix& coo,
    NDArray lhs, NDArray rhs, NDArray out,
    int lhs_target, int rhs_target);
template void SDDMMCoo<kDLGPU, int32_t, 32>(
    const std::string& op, const BcastOff& bcast, const COOMatrix& coo,
    NDArray lhs, NDArray rhs, NDArray out,
    int lhs_target, int rhs_target);
template void SDDMMCoo<kDLGPU, int64_t, 32>(
    const std::string& op, const BcastOff& bcast, const COOMatrix& coo,
    NDArray lhs, NDArray rhs, NDArray out,
    int lhs_target, int rhs_target);
template void SDDMMCoo<kDLGPU, int32_t, 64>(
    const std::string& op, const BcastOff& bcast, const COOMatrix& coo,
    NDArray lhs, NDArray rhs, NDArray out,
    int lhs_target, int rhs_target);
template void SDDMMCoo<kDLGPU, int64_t, 64>(
    const std::string& op, const BcastOff& bcast, const COOMatrix& coo,
    NDArray lhs, NDArray rhs, NDArray out,
    int lhs_target, int rhs_target);

template void SDDMMCooHetero<kDLGPU, int32_t, 16>(
    const std::string& op, const BcastOff& bcast,
    const std::vector<COOMatrix>& vec_coo,
    const std::vector<NDArray>& lhs, const std::vector<NDArray>& rhs,
    std::vector<NDArray> out, int lhs_target, int rhs_target,
    const std::vector<dgl_type_t>& in_eid,
    const std::vector<dgl_type_t>& out_eid);
template void SDDMMCooHetero<kDLGPU, int64_t, 16>(
    const std::string& op, const BcastOff& bcast,
    const std::vector<COOMatrix>& vec_coo,
    const std::vector<NDArray>& lhs, const std::vector<NDArray>& rhs,
    std::vector<NDArray> out, int lhs_target, int rhs_target,
    const std::vector<dgl_type_t>& in_eid,
    const std::vector<dgl_type_t>& out_eid);
template void SDDMMCooHetero<kDLGPU, int32_t, 32>(
    const std::string& op, const BcastOff& bcast,
    const std::vector<COOMatrix>& vec_coo,
    const std::vector<NDArray>& lhs, const std::vector<NDArray>& rhs,
    std::vector<NDArray> out, int lhs_target, int rhs_target,
    const std::vector<dgl_type_t>& in_eid,
    const std::vector<dgl_type_t>& out_eid);
template void SDDMMCooHetero<kDLGPU, int64_t, 32>(
    const std::string& op, const BcastOff& bcast,
    const std::vector<COOMatrix>& vec_coo,
    const std::vector<NDArray>& lhs, const std::vector<NDArray>& rhs,
    std::vector<NDArray> out, int lhs_target, int rhs_target,
    const std::vector<dgl_type_t>& in_eid,
    const std::vector<dgl_type_t>& out_eid);
template void SDDMMCooHetero<kDLGPU, int32_t, 64>(
    const std::string& op, const BcastOff& bcast,
    const std::vector<COOMatrix>& vec_coo,
    const std::vector<NDArray>& lhs, const std::vector<NDArray>& rhs,
    std::vector<NDArray> out, int lhs_target, int rhs_target,
    const std::vector<dgl_type_t>& in_eid,
    const std::vector<dgl_type_t>& out_eid);
template void SDDMMCooHetero<kDLGPU, int64_t, 64>(
    const std::string& op, const BcastOff& bcast,
    const std::vector<COOMatrix>& vec_coo,
    const std::vector<NDArray>& lhs, const std::vector<NDArray>& rhs,
    std::vector<NDArray> out, int lhs_target, int rhs_target,
    const std::vector<dgl_type_t>& in_eid,
    const std::vector<dgl_type_t>& out_eid);

}  // namespace aten
}  // namespace dgl
