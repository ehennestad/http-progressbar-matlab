function mustBeFigureOrEmpty(fig)
    if isempty(fig)
        return
    end

    if ~(isscalar(fig) && isgraphics(fig, 'figure'))
        error('webprogress:validators:InvalidFigure', ...
            'Figure must be a scalar figure handle or empty.')
    end
end
