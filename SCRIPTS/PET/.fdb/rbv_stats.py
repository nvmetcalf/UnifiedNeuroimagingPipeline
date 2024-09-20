import argparse
import nibabel as nib
#from itertools import izip


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('rbv', help='rbv nifti', type=str)
    parser.add_argument('stats', type=str)
    parser.add_argument('out', type=str)

    args = parser.parse_args()

    data = nib.load(args.rbv).get_data().squeeze()
    if data.ndim != 1:
        print(data.shape)
        raise Exception()
    with open(args.stats, 'r') as f, open(args.out, 'w') as g:
        for line, mean in zip(f, data):
            row, index, structure, cls, voxels = line.split()[:5]
            g.write('%3d %4d %-31s %-13s %6d %.3f\n' % (int(row), int(index), structure, cls, int(voxels), mean))

if __name__ == '__main__':
    main()


