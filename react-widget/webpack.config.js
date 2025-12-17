const path = require('path');

module.exports = {
  entry: './src/index.js',
  output: {
    filename: 'widget.js',
    path: path.resolve(__dirname, 'dist'),
    // This allows the widget to be loaded via script tag
    library: 'NepalLocationWidget',
    libraryTarget: 'umd',
    globalObject: 'this'
  },
  module: {
    rules: [
      {
        test: /\.(js|jsx)$/,
        exclude: /node_modules/,
        use: {
          loader: 'babel-loader',
          options: {
            presets: ['@babel/preset-env', '@babel/preset-react']
          }
        }
      },
      {
        test: /\.css$/,
        use: ['style-loader', 'css-loader']
      }
    ]
  },
  resolve: {
    extensions: ['.js', '.jsx']
  }
};
