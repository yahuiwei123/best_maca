import argparse
import numpy as np
import scipy.io as scio

parser = argparse.ArgumentParser()
parser.add_argument("--input_path", type=str, default=None, help="ANTs .mat file")
parser.add_argument("--output_path", type=str, default=None, help="FSL .mat file")

args = parser.parse_args()

ants_mat = args.input_path
fsl_mat = args.output_path

lps2ras = np.array(
    [[1, -1, 1, 1],
     [-1, 1, 1, 1],
     [1, 1, 1, -1],
     [1, 1, 1, 1]])

xyz2ras = np.array([[0.4996, -0.0150, 0.0139, -82.7331],
                    [0.0150, 0.4998, 0.0007, -89.2923],
                    [-0.0139, -0.0003, 0.4998, -16.2598],
                    [0.0000, 0.0000, 0.0000, 1.0000]])

ras2xyz = np.array([[1.9983, 0.0598, -0.0555, 169.7678],
                    [-0.0599, 1.9991, -0.0012, 173.5305],
                    [0.0555, 0.0029, 1.9992, 37.3517],
                    [0.0000, 0.0000, 0.0000, 1.0000]])

# xform = np.array([[0.9992, -0.0299, 0.0277, -26.9212],
#                   [0.0299, 0.9996, 0.0014, -23.5541],
#                   [-0.0278, -0.0006, 0.9996, 46.1223]])

# xyz2ras = np.array([[-0.5, 0, 0, 64],
#                     [0, 0.5, 0, -73],
#                     [0, 0, 0.5, -61.5],
#                     [0, 0, 0, 1]])

# ras2xyz = np.array([[-2, 0, 0, 128],
#                     [0, 2, 0, 147],
#                     [0, 0, 2, 123],
#                     [0, 0, 0, 1]])

data = scio.loadmat(ants_mat)
print(data)
transform = data['AffineTransform_double_3_3']
fixed = data['fixed']

matrix = transform[:9].reshape(3, 3)
translation = transform[9:].reshape(3, 1)
center = fixed.reshape(3, 1)

offset = translation - matrix @ center + center

fsl_matrix = np.zeros((4, 4))
fsl_matrix[:3, :3] = matrix
fsl_matrix[:3, 3] = offset.T
fsl_matrix[3, :3] = center.T
fsl_matrix[3, 3] = 1

fsl_matrix = fsl_matrix * lps2ras
fsl_matrix = ras2xyz @ fsl_matrix @ xyz2ras
np.savetxt(fsl_mat, fsl_matrix, fmt='%.6g')
