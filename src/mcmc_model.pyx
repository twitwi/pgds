#!python
#cython: boundscheck=False
#cython: cdivision=True
#cython: infertypes=True
#cython: initializedcheck=False
#cython: nonecheck=False
#cython: wraparound=False
#distutils: extra_link_args = ['-lgsl', '-lgslcblas']
#distutils: extra_compile_args = -Wno-unused-function -Wno-unneeded-internal-declaration

import sys
import numpy as np
cimport numpy as np
import scipy.stats as st
from numpy.random import randint
from pp_plot import pp_plot


cdef class MCMCModel:

    def __init__(self, object seed=None):

        self.rng = gsl_rng_alloc(gsl_rng_mt19937)

        if seed is None:
            seed = randint(0, sys.maxint) & 0xFFFFFFFF
        gsl_rng_set(self.rng, seed)

    def __dealloc__(self):
        """
        Free GSL random number generator.
        """

        gsl_rng_free(self.rng)

    cdef list _get_variables(self):
        """
        Return variable names, values, and sampling methods for testing.

        Example:

        return [('foo', self.foo, self._sample_foo),
                ('bar', self.bar, self._sample_bar)]
        """
        pass

    def get_state(self):
        """
        Wrapper around _get_variables(...).

        Returns only the names and values of variables (not update funcs).
        """
        for (k, v, update_func) in self._get_variables():
            if np.isscalar(v):
                yield k, v
            else:
                yield k, np.array(v)

    cdef void _generate_state(self):
        """
        Generate internal state.
        """

        pass

    cdef void _generate_data(self):
        """
        Generate data given internal state.
        """

        pass

    cdef void _init_state(self):
        """
        Initialize internal state.
        """

        pass

    cdef void _print_state(self):
        """
        Print internal state.
        """

        pass

    cdef void _update(self, int num_itns, int verbose, dict schedule):
        """
        Perform inference.
        """

        cdef:
            int n

        for n in range(num_itns):
            for k, _, update_func in self._get_variables():
                if k not in schedule.keys() or n >= schedule[k]:
                    update_func(self)
            if verbose != 0:
                print n
                if (n + 1) % 1 == 0:
                    self._print_state()

    cpdef void update(self, int num_itns, int verbose, dict schedule={}):
        """
        Thin wrapper around _update(...).
        """
        self._update(num_itns, verbose, schedule)

    cdef void _test(self,
                    int num_samples,
                    str method='geweke',
                    dict schedule={}):
        """
        Perform Geweke testing or Schein testing.
        """

        cdef:
            int n
            dict funcs, fwd, rev

        funcs = {
            'Arith. Mean': np.mean,
            # 'Geom. Mean': lambda x: np.exp(np.log1p(x).mean()),
            'Entropy mean': lambda x: np.mean(st.entropy(x)),
            'Var.': np.var,
            'Max.': np.max
        }

        fwd, rev = {}, {}
        for k, v, _ in self._get_variables():
            if np.isscalar(v):
                fwd[k] = np.empty(num_samples)
                rev[k] = np.empty(num_samples)
            else:
                fwd[k] = {}
                rev[k] = {}
                for f in funcs:
                    fwd[k][f] = np.empty(num_samples)
                    rev[k][f] = np.empty(num_samples)

        if method == 'schein':
            for n in range(num_samples):
                self._generate_state()
                self._generate_data()
                self._calc_funcs(funcs, n, fwd)

                self._update(5, 0, schedule)
                self._generate_data()
                self._calc_funcs(funcs, n, rev)

                if n % 500 == 0:
                    print n
        else:
            for n in range(num_samples):
                self._generate_state()
                self._generate_data()
                self._calc_funcs(funcs, n, fwd)
                if n % 500 == 0:
                    print n

            self._generate_state()
            for n in range(num_samples):
                self._generate_data()
                self._update(1, 0, schedule)
                self._calc_funcs(funcs, n, rev)
                if n % 500 == 0:
                    print n

        for k, _, _ in self._get_variables():
            if not np.isinf(schedule[k]):
                pp_plot(fwd[k], rev[k], k)

    cdef void _calc_funcs(self, dict funcs, int n, dict out):
        """
        Helper function for _test. Calculates and stores functions of variables.
        """

        for k, v, _ in self._get_variables():
            if np.isscalar(v):
                out[k][n] = v
            else:
                for f, func in funcs.iteritems():
                    out[k][f][n] = func(v)

    cpdef void geweke(self, int num_samples):
        """
        Wrapper around _test(...).
        """

        self._test(num_samples, 'geweke')

    cpdef void schein(self, int num_samples, dict schedule={}):
        """
        Wrapper around _test(...).
        """
        self._test(num_samples, 'schein', schedule)
